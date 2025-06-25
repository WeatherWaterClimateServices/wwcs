import datetime
import json

import pytest

import bot


humanID = 99942
siteID = 'TESTSITE'
telegramID = 42


class FakeMessage:
    
    def __init__(self, chat, message_id, text):
        self.chat = chat
        self.message_id = message_id
        self.text = text

class FakeChat:

    def __init__(self, chat_id):
        self.id = chat_id
        self.message_id = 0

class FakeBot:

    def __init__(self):
        self.chats = {}

    async def send_message(self, chat_id, message):
        chat = self.chats.get(chat_id)
        if chat is None:
            chat = FakeChat(chat_id)
            self.chats[chat_id] = chat

        chat.message_id += 1
        return FakeMessage(chat, chat.message_id, message)

    def register_next_step_handler(self, message, callback, *args, **kwargs):
        chat = message.chat
        chat.callback = callback
        chat.args = args
        chat.kwargs = kwargs

    def fake_message(self, chat_id, text):
        chat = self.chats.get(chat_id)
        chat.message_id += 1
        message = FakeMessage(chat, chat.message_id, text)
        chat.callback(message, *chat.args, **chat.kwargs)


bot.bot = FakeBot()  # Mock


def cleanup():
    with bot.get_cursor(commit=True) as cursor:
        cursor.execute('DELETE FROM SitesHumans.Humans WHERE humanID = %s;', [str(humanID)])
        cursor.execute('DELETE FROM SitesHumans.Sites WHERE siteID = %s;', [siteID])
        cursor.execute('DELETE FROM WWCServices.Irrigation WHERE siteID = %s;', [siteID])

@pytest.fixture()
def data():
    # Init data
    with bot.get_cursor(commit=True) as cursor:
        # SitesHumans.Humans
        columns = 'humanID, telegramID, phone, firstName, project'
        sql = f'INSERT INTO SitesHumans.Humans ({columns}) VALUES (%s, %s, %s, %s, %s);'
        values = [str(humanID), telegramID, 42, 'Test user', '']
        cursor.execute(sql, values)

        # SitesHumans.Sites
        columns = 'siteID, irrigation, fieldproperties, latitude, longitude, altitude'
        sql = f'INSERT INTO SitesHumans.Sites ({columns}) VALUES (%s, %s, %s, %s, %s, %s);'
        fieldproperties = {"area": 2, "type": "channel", "humanID": humanID}
        values = [siteID, 1, json.dumps(fieldproperties), 0, 0, 0]
        cursor.execute(sql, values)

        # WWCServices.Irrigation
        columns = 'siteID, date, irrigationNeed'
        sql = f'INSERT INTO WWCServices.Irrigation ({columns}) VALUES (%s, %s, %s);'
        values = [siteID, datetime.date.today(), 71]
        cursor.execute(sql, values)

    try:
        yield
    finally:
        cleanup()


#
# Tests
#

@pytest.mark.asyncio
async def test_telebot():
    chat_id = 123
    msg1 = await bot.bot.send_message(chat_id, "Test1")
    assert msg1.text == 'Test1'
    msg2 = await bot.bot.send_message(chat_id, "Test2")
    assert msg2.text == 'Test2'
    assert msg1.message_id != msg2.message_id

    class FakeCallback:
        def __init__(self):
            self.called = False

        def callback(self, message):
            self.called = True

    fake_callback = FakeCallback()
    bot.bot.register_next_step_handler(msg2, fake_callback.callback)

    assert fake_callback.called is False
    bot.bot.fake_message(chat_id, '10')
    assert fake_callback.called is True


def test_data(data):
    with bot.get_cursor() as cursor:
        # SitesHumans.Humans
        sql = 'SELECT humanID, telegramID, phone, firstName FROM SitesHumans.Humans WHERE humanID = %s'
        cursor.execute(sql, [str(humanID)])
        rows = cursor.fetchall()
        assert len(rows) == 1
        assert rows[0] == (str(humanID), telegramID, 42, 'Test user')

        # SitesHumans.Sites
        sql = """
        SELECT siteID, irrigation, fieldproperties
        FROM SitesHumans.Sites
        WHERE JSON_EXTRACT(fieldproperties, '$.humanID') = %s
        """
        cursor.execute(sql, [humanID])
        rows = cursor.fetchall()
        assert len(rows) == 1
        sid, irrigation, fieldproperties = rows[0]
        assert sid == siteID
        assert irrigation == 1
        assert json.loads(fieldproperties) == {"area": 2, "type": "channel", "humanID": humanID}

        # WWCServices.Irrigation
        sql = 'SELECT siteID, date, irrigationNeed FROM WWCServices.Irrigation WHERE siteID = %s'
        cursor.execute(sql, [siteID])
        rows = cursor.fetchall()
        assert len(rows) == 1
        print(rows)
        assert rows[0] == (siteID, datetime.date.today(), 71)


def test_rows(data):
    rows = bot.get_rows()
    assert len(rows) == 1
    sid, hid, phone, firstName, irrigation, date, irrigationNeed, tid, fieldtype, area = rows[0]
    assert sid == siteID
    assert int(hid) == humanID
    assert tid == telegramID


@pytest.mark.parametrize("irrigation_need, water_level, area, fieldtype, irrigation_time", [
    (10, 10, 2, "channel", 334),
    (10, 10, 2, "traditional", 0),
])
def test_calculate(irrigation_need, water_level, area, fieldtype, irrigation_time):
    assert bot.calculate_irrigation_time(irrigation_need, water_level, area, fieldtype) == irrigation_time


def test_save(data):
    with bot.get_cursor() as cursor:
        sql = 'SELECT irrigationApp FROM WWCServices.Irrigation WHERE siteID = %s AND date = CURRENT_DATE()'
        cursor.execute(sql, [siteID])
        rows = cursor.fetchall()
        assert len(rows) == 1
        assert rows[0] == (0,)

    bot.convert_and_save_irrigation_data(siteID, 15, 2, "channel")

    with bot.get_cursor() as cursor:
        sql = 'SELECT irrigationApp FROM WWCServices.Irrigation WHERE siteID = %s AND date = CURRENT_DATE()'
        cursor.execute(sql, [siteID])
        rows = cursor.fetchall()
        assert len(rows) == 1
        assert rows[0] == (1800000,)


@pytest.mark.asyncio
async def test_irrigation(data):
    with bot.get_cursor() as cursor:
        sql = 'SELECT irrigationApp FROM WWCServices.Irrigation WHERE siteID = %s AND date = CURRENT_DATE()'
        cursor.execute(sql, [siteID])
        rows = cursor.fetchall()
        assert len(rows) == 1
        assert rows[0] == (0,)

    await bot.check_irrigation()
    chat_id = telegramID
    bot.bot.fake_message(chat_id, '10')  # water level
    bot.bot.fake_message(chat_id, '15')  # actual minutes

    with bot.get_cursor() as cursor:
        sql = 'SELECT irrigationApp FROM WWCServices.Irrigation WHERE siteID = %s AND date = CURRENT_DATE()'
        cursor.execute(sql, [siteID])
        rows = cursor.fetchall()
        assert len(rows) == 1
        assert rows[0] == (1800000,) # XXX
