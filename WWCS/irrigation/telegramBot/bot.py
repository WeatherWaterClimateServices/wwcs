import asyncio
import contextlib
import datetime
import gettext
import os
import pathlib
import time

# Requirements
import MySQLdb
import telebot.async_telebot
from dotenv import load_dotenv


# Configuration
load_dotenv()
ENV = os.environ.get('ENV')
USERNAME = os.environ.get('USERNAME', 'wwcs')
PASSWORD = os.environ.get('PASSWORD')
BOT_TOKEN = os.environ['BOT_TOKEN']
LANGUAGE = os.environ.get('LANGUAGE', 'en')

# Initialize gettext
root = pathlib.Path(__file__).parent
translation = gettext.translation(
    'messages',                 # The domain, messages is the default
    localedir=root / 'locale',  # Where the translation files are stored
    languages=[LANGUAGE],       # We only support one language at a time
    fallback=True,              # Return the source id if not translation file is found
)
_ = translation.gettext

class Handler:

    def __init__(self, callback, args, kwargs):
        self.callback = callback
        self.args = args
        self.kwargs = kwargs


class MyBot(telebot.async_telebot.AsyncTeleBot):

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.__handlers = {}

    def register_next_step_handler(self, message, callback, *args, **kwargs):
        self.__handlers[message.chat.id] = Handler(callback, args, kwargs)

    def clear_step_handler(self, message):
        self.__handlers.pop(message.chat.id)

    def get_step_handler(self, msg):
        return self.__handlers.get(msg.chat.id)


bot = MyBot(BOT_TOKEN)


def connect_db():
    return MySQLdb.connect("localhost", USERNAME, PASSWORD)


@contextlib.contextmanager
def get_cursor(commit=False):
    conn = connect_db()
    cursor = conn.cursor()
    yield cursor
    cursor.close()
    if commit:
        conn.commit()
    conn.close()


def update_irrigationApp(site_id, value):
    print(f'SAVE siteID={site_id} irrigationApp={value}')
    sql = """
    UPDATE WWCServices.Irrigation SET irrigationApp = %s
    WHERE siteID = %s AND date = DATE_SUB(CURDATE(), INTERVAL 1 DAY)
    """
    with get_cursor(commit=True) as cursor:
        cursor.execute(sql, (value, site_id))
    print('OK')


def get_rows():
    sql_query = """
    SELECT
        s.siteID,
        h.humanID,
        h.phone,
        h.firstName,
        s.irrigation,
        i.date,
        i.irrigationNeed,
        h.telegramID,
        JSON_UNQUOTE(JSON_EXTRACT(s.fieldproperties, '$.type')) type,
        JSON_EXTRACT(s.fieldproperties, '$.area') area
    FROM SitesHumans.Sites s
        JOIN SitesHumans.Humans h on JSON_EXTRACT(s.fieldproperties, '$.humanID') = h.humanID
        JOIN WWCServices.Irrigation i on i.siteID = s.siteID
    WHERE s.irrigation = 1 AND i.PHIc < i.PHIt AND i.irrigationApp = 0
    AND i.date = DATE_SUB(CURDATE(), INTERVAL 1 DAY)
    """

    with get_cursor() as cursor:
        cursor.execute(sql_query)
        return cursor.fetchall()


async def check_irrigation():
    for row in get_rows():
        site_id, human_id, phone, first_name, irrigation, date, irrigation_need, telegram_id, fieldtype, area = row

        # For testing, force a developers id
        #telegram_id = 5257578161  # jdavid
        #telegram_id = -4160131435

        area = float(area)
        if irrigation == 1:
            print(f'{human_id=} {site_id=} {fieldtype=}')

            if fieldtype == 'channel':
                message = _("Please send the current water level")
                msg = await bot.send_message(telegram_id, message)
                bot.register_next_step_handler(msg, process_channel_begin, site_id, irrigation_need, area, fieldtype)

            #add new condition counter - 22.05.2024
            elif fieldtype == 'counter':
                message = _("Hello. Please start irrigating your land today. Send your water meter reading before irrigating your land.")
                msg = await bot.send_message(telegram_id, message)
                bot.register_next_step_handler(msg, process_counter_begin, site_id, irrigation_need, area, fieldtype)

            elif fieldtype == 'pump':
                message = _("Hello. Please start irrigating your land today. Send your water meter reading before irrigating your land.")
                msg = await bot.send_message(telegram_id, message)
                bot.register_next_step_handler(msg, process_pump_begin, site_id, irrigation_need, area, fieldtype)
                # print(f'Unexpected {fieldtype=}') # TODO

            elif fieldtype == 'traditional':
                message = _("Hello. When the irrigation of the land is finished, please send me the actual M3 irrigation?")
                await bot.send_message(telegram_id, message)
                bot.register_next_step_handler(msg, process_traditional, site_id, irrigation_need, area, fieldtype)

            else:
                print(f'Unexpected {fieldtype=}')
        else:
            print(f"No irrigation needed for site {site_id}")


@bot.message_handler(func=lambda message: True)
async def catch_all(message):
    print('ECHO', message.chat.id, message.text)
    handler = bot.get_step_handler(message)
    if handler is not None:
        bot.clear_step_handler(message)
        await handler.callback(message, *handler.args, **handler.kwargs)
    else:
        print(f'msg from {message.chat.id}: {message.text}')


#CHANNEL
async def process_channel_begin(message, site_id, irrigation_need, area, fieldtype):
    print(f'process_channel_begin: {message.text}')
    try:
        water_level = int(message.text)
    except ValueError:
        message = _("Please write the number, not the text.")
        msg = await bot.send_message(message.chat.id, message)
        bot.register_next_step_handler(msg, process_channel_begin, site_id, irrigation_need, area, fieldtype)
        return

    irrigation_time = calculate_irrigation_time(irrigation_need, water_level, area, fieldtype)
    message = _("Please start watering now, you need to irrigate the land for {irrigation_time} minutes.")
    message = message.format(irrigation_time=irrigation_time)
    await bot.send_message(message.chat.id, message)

    message = _("When the irrigation of the land is finished, please send how many minutes you actually irrigated?")
    await bot.send_message(message.chat.id, message)
    bot.register_next_step_handler(message, process_channel_end, site_id, area, water_level, fieldtype)


async def process_channel_end(message, site_id, area, water_level, fieldtype):
    print(f'process_channel_end: {message.text}')
    try:
        actual_minutes = int(message.text)
    except ValueError:
        message = _("Please write the number, not the text.")
        msg = await bot.send_message(message.chat.id, message)
        bot.register_next_step_handler(msg, process_channel_end, site_id, area, water_level, fieldtype)
        return
    convert_and_save_irrigation_data(site_id, actual_minutes, area, fieldtype)
    message = _("Thank you for your cooperation! Your irrigation data has been recorded.")
    await bot.send_message(message.chat.id, message)


#COUNTER
async def process_counter_begin(msg, site_id, irrigation_need, area, fieldtype):
    print(f'process_counter_begin: {msg.text}')
    try:
        counter_begin = int(msg.text)
    except ValueError:
        msg = await bot.send_message(msg.chat.id, 'Лутфан рақамро нависед, на матн.')
        bot.register_next_step_handler(msg, process_counter_begin, site_id, irrigation_need, area, fieldtype)
        return

    M3_need = calculate_irrigation_need(irrigation_need, area, fieldtype)
    cubic_metres = counter_begin + (M3_need / 10)
    message = _("You should irrigate the land until your water meter reading reaches {cubic_metres} M3.")
    message = message.format(cubic_metres=cubic_metres)
    await bot.send_message(msg.chat.id, message)

    message = _("What was the water meter reading after the land was irrigated?")
    await bot.send_message(msg.chat.id, message)
    bot.register_next_step_handler(msg, process_counter_end, site_id, irrigation_need, area, fieldtype, counter_begin)


async def process_counter_end(message, site_id, irrigation_need, area, fieldtype, counter_begin):
    try:
        counter_end = int(message.text)
    except ValueError:
        message = _("Please write the number, not the text.")
        msg = await bot.send_message(message.chat.id, message)
        bot.register_next_step_handler(msg, process_counter_end, site_id, irrigation_need, area, fieldtype)
        return

    # Save in the database
    update_irrigationApp(site_id, (counter_end - counter_begin) * 10)
    message = _("The {value} indicator has been recorded in the database.")
    message = message.format(value=counter_end)
    await bot.send_message(message.chat.id, message)

#PUMP
async def process_pump_begin(msg, site_id, irrigation_need, area, fieldtype):
    print(f'process_pump_begin: {msg.text}')
    try:
        pump_begin = int(msg.text)
    except ValueError:
        message = _("Please write the number, not the text.")
        msg = await bot.send_message(msg.chat.id, message)
        bot.register_next_step_handler(msg, process_pump_begin, site_id, irrigation_need, area, fieldtype)
        return

    M3_need = calculate_irrigation_need(irrigation_need, area, fieldtype)
    cubic_metres = pump_begin + (M3_need / 10)
    message = _("You should irrigate the land until your water meter reads {cubic_metres} M3.")
    message = message.format(cubic_metres=cubic_metres)
    await bot.send_message(msg.chat.id, message)

    message = _("What was the water meter reading after the land was irrigated?")
    await bot.send_message(msg.chat.id, message)
    bot.register_next_step_handler(msg, process_counter_end, site_id, irrigation_need, area, fieldtype, pump_begin)


async def process_pump_end(message, site_id, irrigation_need, area, fieldtype, pump_begin):
    try:
        pump_end = int(message.text)
    except ValueError:
        message = _("Please write the number, not the text.")
        msg = await bot.send_message(message.chat.id, message)
        bot.register_next_step_handler(msg, process_counter_end, site_id, irrigation_need, area, fieldtype)
        return

    # Save in the database
    update_irrigationApp(site_id, (pump_end - pump_begin) * 10)
    message = _("The {value} indicator has been recorded in the database.")
    message = message.format(value=pump_end)
    await bot.send_message(message.chat.id, message)


#TRADITION
async def process_traditional(message, site_id, irrigation_need, area, fieldtype):
    try:
        traditional_end = int(message.text)
    except ValueError:
        message = _("Please write the number, not the text.")
        msg = await bot.send_message(message.chat.id, message)
        bot.register_next_step_handler(msg, process_traditional, site_id, irrigation_need, area, fieldtype)
        return

    # M3_need = calculate_irrigation_need(irrigation_need, area, fieldtype)
    # await bot.send_message(message.chat.id, "Ташаккур барои ҳамкорӣ ! Маълумоти обёрии шумо сабт шуд.")

    # Save in the database
    update_irrigationApp(site_id, traditional_end * 10)
    message = _("The {value} indicator has been recorded in the database.")
    message = message.format(value=traditional_end)
    await bot.send_message(message.chat.id, message)


def calculate_irrigation_time(irrigation_need, water_level, area, fieldtype):
    if irrigation_need != 0 and fieldtype == 'channel':
        M3_need = (irrigation_need * area * 10 * (50 / 100)) / (65 / 100)
        irrigation_time = M3_need / (0.6 * 60) #0.6 is a M3_Flow
        return irrigation_time

    return 0


def calculate_irrigation_need(irrigation_need, area, fieldtype):
    if irrigation_need != 0 and fieldtype in ['pump', 'counter']: #add fieldtype = counter
        # 50% is a Percent Wetted Area. 65% is a Irrigation Efficiency
        M3_need = (irrigation_need * 10 * area * (50 / 100)) / (65 / 100)
        return round(M3_need)

def convert_and_save_irrigation_data(site_id, actual_minutes, area, fieldtype):
    assert fieldtype == 'channel'

    M3 = actual_minutes * 0.6 * 60
    milliliters =  (M3 * (65 / 100)) / (10 * area * (50 / 100))

    print(f'SAVE siteID={site_id} irrigationApp={milliliters}')
    update_irrigationApp(site_id, milliliters)


# # Запланируем проверку каждый день в 7 утра

async def run_at(func, filter):
    while True:
        # Run every minute
        now = time.time()
        at = (now - now % 60) + 60
        delay = at - now
        await asyncio.sleep(delay)

        now = datetime.datetime.now()
        if filter(now):
            await func()


async def main():
    asyncio.create_task(
        run_at(
            check_irrigation,
            lambda x: x.hour == 7 and x.minute == 0
            #lambda x: x.second % 5 == 0 # 0s 5s 10s 15s
            #lambda x: True
        )
    )
    await bot.polling()


if __name__ == '__main__':
    asyncio.run(main())
