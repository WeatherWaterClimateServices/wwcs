from datetime import datetime, timedelta
import asyncio
import gettext
import os
import pathlib

# Requirements
from apscheduler.jobstores.base import JobLookupError
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.date import DateTrigger
from apscheduler.triggers.interval import IntervalTrigger
from databases import Database
from telebot import types
from telebot.async_telebot import AsyncTeleBot
import dotenv


# Configuration
dotenv.load_dotenv()
DB_USERNAME = os.environ.get('DB_USERNAME', 'wwcs')
DB_PASSWORD = os.environ['DB_PASSWORD']
BOT_TOKEN = os.environ['BOT_TOKEN']
LANGUAGE = os.environ.get('LANGUAGE', 'en')
TIMEZONE = os.environ.get('TIMEZONE')  # Defaults to local timezone

# Database
DATABASE_URL = f'mysql+asyncmy://{DB_USERNAME}:{DB_PASSWORD}@localhost:3306/WWCServices'
database = Database(DATABASE_URL)

# Initialize gettext
root = pathlib.Path(__file__).parent
translation = gettext.translation(
    'messages',                 # The domain, messages is the default
    localedir=root / 'locale',  # Where the translation files are stored
    languages=[LANGUAGE],       # We only support one language at a time
    fallback=True,              # Return the source id if not translation file is found
)
_ = translation.gettext


scheduler = AsyncIOScheduler()

class NotificationManager:

    def add_job(self, chat_id, job_type, func, trigger):
        job_id = f"{job_type}_{chat_id}"
        self.remove_job(chat_id, job_type)
        scheduler.add_job(func, trigger, id=job_id, args=[chat_id])

    def remove_job(self, chat_id, job_type):
        job_id = f"{job_type}_{chat_id}"
        try:
            scheduler.remove_job(job_id)
        except JobLookupError:
            pass

    def remove_all_jobs(self, chat_id):
        for job_type in ['water_check', 'polyv_complete']:
            self.remove_job(chat_id, job_type)


notification_manager = NotificationManager()


# Инициализация бота
bot = AsyncTeleBot(BOT_TOKEN)

# Словари для хранения состояний
user_states = {}
user_irrigation_data = {}  # Для хранения данных о поливе

# Таблица расхода воды (уровень в см -> расход в м³/мин)
WATER_FLOW_RATES = {
    1: 0.0008,
    2: 0.0048,
    3: 0.01,
    4: 0.03,
    5: 0.05,
    6: 0.07,
    7: 0.11,
    8: 0.15,
    9: 0.20,
    10: 0.27,
    11: 0.34,
    12: 0.42,
    13: 0.51,
    14: 0.62,
    15: 0.73,
    16: 0.86,
    17: 1.00,
    18: 1.15,
    19: 1.32,
    20: 1.50,
    21: 1.70,
    22: 1.91,
    23: 2.13,
    24: 2.37,
    25: 2.63,
}


async def get_irrigation_data(chat_id=None):
    query = """
    SELECT
        s.siteID,
        h.humanID,
        h.phone,
        h.firstName,
        s.irrigation,
        i.date,
        i.irrigationNeed,
        h.telegramID,
        JSON_UNQUOTE(JSON_EXTRACT(s.fieldproperties, '$.type')) AS type,
        JSON_EXTRACT(s.fieldproperties, '$.area') AS area,
        JSON_EXTRACT(s.fieldproperties, '$.IE') AS ie,
        JSON_EXTRACT(s.fieldproperties, '$.WA') AS wa
    FROM SitesHumans.Sites s
        JOIN SitesHumans.Humans h ON JSON_UNQUOTE(JSON_EXTRACT(s.fieldproperties, '$.humanID')) = h.humanID
        JOIN WWCServices.Irrigation i ON i.siteID = s.siteID
    WHERE
        s.irrigation = 1
        AND i.PHIc < i.PHIt
        AND i.irrigationApp = 0
        AND i.date = DATE_SUB(CURDATE(), INTERVAL 1 DAY)
    """

    if chat_id:
        # TODO The telegramID column should be unique
        query += f' AND telegramID = {chat_id}'
        row = await database.fetch_one(query=query)
        if row is None:
            await bot.send_message(chat_id, _("❌ Your data was not found in the system"))
        return row

    return await database.fetch_all(query=query)


BUTTONS = {
    "send_recommendation": _("Send recommendation"),
    "no_water": _("No water"),
    "save_data": _("Save data"),
}


def create_reply_keyboard():
    markup = types.ReplyKeyboardMarkup(row_width=2, resize_keyboard=True)
    buttons = [
        types.KeyboardButton(BUTTONS["send_recommendation"]),
        types.KeyboardButton(BUTTONS["no_water"]),
        types.KeyboardButton(BUTTONS["save_data"]),
    ]
    markup.add(*buttons)
    return markup


def start_irrigation_notifications(chat_id):
    notification_manager.add_job(chat_id, 'water_check', send_water_check_notification,
                                 trigger=IntervalTrigger(minutes=15))


async def send_water_check_notification(chat_id):
    """Отправляет уведомление о проверке уровня воды"""
    if chat_id in user_irrigation_data:
        message = _("🔄 Please check the current water level in the channel and send its value")
        await bot.send_message(chat_id, message)


def schedule_polyv_completion_notification(chat_id, hours, minutes):
    completion_time = datetime.now() + timedelta(hours=hours, minutes=minutes)
    notification_manager.add_job(chat_id, 'polyv_complete', notify_polyv_completion,
                                 trigger=DateTrigger(run_date=completion_time))


async def notify_polyv_completion(chat_id):
    if chat_id in user_irrigation_data and user_irrigation_data[chat_id].get('is_active', False):
        message = _("⏰ Watering time is over! Please click the 'Save data' button to save the results.")
        await bot.send_message(chat_id, message)
        notification_manager.remove_job(chat_id, 'water_check')


async def check_irrigation(chat_id):
    row = await get_irrigation_data(chat_id)
    if row is not None:
        m3_needed = (float(row['irrigationNeed']) * 10 * float(row['area']) * float(row['wa'])) / float(row['ie'])

        row_type = row['type']
        if row_type == "channel":
            text = _(
                "🌤 Good morning, {first_name}!\n"
                "Your plot is ready for irrigation.\n"
                "💧 Water required: {water:.2f} m³"
            )

        elif row_type == "counter":
            text = _(
                "🌤 Good morning, {first_name}!\n"
                "Your plot is ready for irrigation.\n"
                "💧 Water required: {water:.2f} m³"
            )

        elif row_type == "traditional":
            text = _(
                "Hello, {first_name}!\n"
                "If your irrigation complete please push Save data button and enter you counter numbers Before and After irrigation\n"
                "and save your data"
            )

        else:
            text = _("ERROR!")

        message = text.format(first_name=row['firstName'], water=round(m3_needed, 2))
        markup = create_reply_keyboard()
        await bot.send_message(chat_id, message, reply_markup=markup)


async def check_all_users():
    notified_users = set()
    for row in await get_irrigation_data():
        if row['telegramID'] not in notified_users:
            chat_id = row['telegramID']
            try:
                await check_irrigation(chat_id)
                notified_users.add(chat_id)
            except Exception as e:
                print(f"Notification error for {chat_id}: {e}")


async def calculate_irrigation(chat_id, water_level, irrigation_need, area, ie, wa):
    total_needed_m3 = (irrigation_need * area * 10 * wa) / ie

    if chat_id not in user_irrigation_data:
        user_irrigation_data[chat_id] = {
            'start_time': datetime.now(),
            'last_update': datetime.now(),
            'current_level': water_level,
            'total_needed_m3': total_needed_m3,
            'total_used_m3': 0,
            'history': [(water_level, datetime.now())],
            'is_active': True,
        }

        # We launch notifications only for new watering
        start_irrigation_notifications(chat_id)
    else:
        data = user_irrigation_data[chat_id]
        time_elapsed = (datetime.now() - data['last_update']).total_seconds()
        flow_rate = WATER_FLOW_RATES.get(data['current_level'], 0)

        m3_used = flow_rate * (time_elapsed / 60)
        data['total_used_m3'] += m3_used
        data['history'].append((water_level, datetime.now()))
        data['last_update'] = datetime.now()
        data['current_level'] = water_level
        data['is_active'] = True

    remaining_m3 = max(0, total_needed_m3 - user_irrigation_data[chat_id]['total_used_m3'])
    flow_rate = WATER_FLOW_RATES.get(water_level, 0)
    remaining_time = (remaining_m3 / flow_rate) / 60 if flow_rate > 0 else 0

    # Планируем уведомление о завершении
    if remaining_time > 0:
        hours = int(remaining_time)
        minutes = int((remaining_time - hours) * 60)
        schedule_polyv_completion_notification(chat_id, hours, minutes)

    return {
        'used_m3': user_irrigation_data[chat_id]['total_used_m3'],
        'remaining_m3': remaining_m3,
        'remaining_time': remaining_time,
        'is_completed': remaining_m3 <= 0,
    }


@bot.message_handler(commands=['start'])
async def start(message):
    markup = create_reply_keyboard()
    await bot.send_message(message.chat.id, "Select action:", reply_markup=markup)
    await check_irrigation(message.chat.id)


@bot.message_handler(func=lambda message: message.text == BUTTONS["send_recommendation"])
async def handle_recommendation(message):
    chat_id = message.chat.id
    row = await get_irrigation_data(chat_id)
    if row is not None:
        if row['type'] == "channel":
            user_states[chat_id] = "waiting_for_water_level"
            await bot.send_message(chat_id, _("Enter the current water level in the channel (in cm):"))

        elif row['type'] == "counter":
            user_states[chat_id] = "waiting_for_counter_start"
            await bot.send_message(chat_id, _("Please, send the counter value before irrigation (m³):"))

        else:
            await send_recommendation(
                chat_id,
                row['type'],
                float(row['irrigationNeed']),
                float(row['area']),
                float(row['ie']),
                float(row['wa'])
            )


@bot.message_handler(func=lambda message: user_states.get(message.chat.id) == 'waiting_for_counter_start')
async def handle_counter_start(message):
    chat_id = message.chat.id
    try:
        row = await get_irrigation_data(chat_id)
        if row is not None:
            start_counter = float("".join(filter(lambda x: x.isdigit() or x == '.', message.text)))
            m3_needed = (float(row['irrigationNeed']) * 10 * float(row['area'])) * float(row['wa']) / float(row['ie'])
            target_counter = start_counter + m3_needed

            await bot.send_message(
                chat_id,
                _("Irrigate untill you counter is: {target_counter:.2f} m³\n"
                  "Water need: {m3_needed:.2f} m³"
                  ).format(target_counter=target_counter,
                           m3_needed=m3_needed)
            )

            # Сохраняем начальные показания для последующего расчета
            user_irrigation_data[chat_id] = {
                'start_counter': start_counter,
                'target_counter': target_counter,
                'is_active': True,
                'last_update': datetime.now(),
            }
            user_states[chat_id] = None
    except ValueError:
        await bot.send_message(chat_id, _("⚠️ Please, type number (125.5)"))


@bot.message_handler(func=lambda message: user_states.get(message.chat.id) == 'waiting_for_water_level')
async def handle_water_level(message):
    chat_id = message.chat.id
    try:
        water_level = float("".join(filter(lambda x: x.isdigit() or x == '.', message.text)))

        # Проверяем что уровень воды в допустимом диапазоне
        if water_level < 1 or water_level > 25:
            await bot.send_message(
                chat_id,
                _("⚠️ Incorrect water level! Acceptable values from 1 to 25 cm.\n"
                  "Please enter the correct value:")
            )
            return  # Не продолжаем обработку

        row = await get_irrigation_data(chat_id)
        if row is not None:
            calculation = await calculate_irrigation(
                chat_id,
                water_level,
                float(row['irrigationNeed']),
                float(row['area']),
                float(row['ie']),
                float(row['wa']),
            )

            if calculation['is_completed']:
                msg = _("✅ Irrigation completed! Enough water.")
            else:
                hours = int(calculation['remaining_time'])
                minutes = int((calculation['remaining_time'] - hours) * 60)

                msg = _(
                    "💦 Current level: {water_level} cm\n"
                    "⏱ Time left: {hours}h {minutes}m\n"
                    "📊 Used: {used_m3:.2f} m³ of {total_m3:.2f} m³"
                ).format(
                    water_level=water_level,
                    hours=hours,
                    minutes=minutes,
                    used_m3=calculation['used_m3'],
                    total_m3=calculation['used_m3'] + calculation['remaining_m3'],
                )

            await bot.send_message(chat_id, msg)
            user_states[chat_id] = None
    except ValueError:
        await bot.send_message(chat_id, _("⚠️ Please enter a valid number (water level in cm)"))


@bot.message_handler(func=lambda message: message.text == BUTTONS["save_data"])
async def handle_send_data(message):
    chat_id = message.chat.id

    # Stop all notifications
    notification_manager.remove_all_jobs(chat_id)

    row = await get_irrigation_data(chat_id)
    if row is not None:
        if row['type'] == "counter":
            await bot.send_message(chat_id, _("Please, send your counter number after irrigation (m³):"))
            user_states[chat_id] = "waiting_for_counter_end"

        elif row['type'] == "traditional":
            await bot.send_message(chat_id, _("Please, send your counter number BEFORE irrigation (m³)"))
            user_states[chat_id] = "waiting_for_traditional_start"

        elif row['type'] == "channel":
            # Для channel сразу рассчитываем и сохраняем данные
            if chat_id in user_irrigation_data and user_irrigation_data[chat_id].get('is_active', False):
                try:
                    data = user_irrigation_data[chat_id]
                    time_elapsed = (datetime.now() - data['last_update']).total_seconds()
                    flow_rate = WATER_FLOW_RATES.get(data['current_level'], 0)
                    additional_used = flow_rate * (time_elapsed / 60)
                    data['total_used_m3'] += additional_used

                    area = float(row['area'])
                    actual_mm = (data['total_used_m3'] * float(row['ie'])) / (10 * area * float(row['wa']))

                    query = """
                        UPDATE WWCServices.Irrigation SET irrigationApp = :actual_mm
                        WHERE siteID = :siteID AND date = DATE_SUB(CURDATE(), INTERVAL 1 DAY)
                    """
                    values = {'actual_mm': actual_mm, 'siteID': row['siteID']}
                    await database.execute(query=query, values=values)

                    message = _("✅ Data saved! Used: {used_m3:.2f} m³").format(used_m3=data['total_used_m3'])
                    await bot.send_message(chat_id, message)

                    data['is_active'] = False
                    return
                except Exception as e:
                    print(f"Error while saving: {str(e)}")
                    await bot.send_message(chat_id, _("⚠️ Error saving data"))
            else:
                await bot.send_message(chat_id, _("❌ No active irrigation session found"))

        else:
            await bot.send_message(chat_id, _("Wrong fieldtype"))


@bot.message_handler(func=lambda message: user_states.get(message.chat.id) == 'waiting_for_traditional_start')
async def handle_traditional_start(message):
    chat_id = message.chat.id
    try:
        start_counter = float("".join(filter(lambda x: x.isdigit() or x == '.', message.text)))

        user_irrigation_data[chat_id] = {
            'start_counter': start_counter,
            'type': "traditional"
        }

        await bot.send_message(chat_id, _("Now send counter value AFTER irrigation (m³)"))
        user_states[chat_id] = "waiting_for_traditional_end"
    except ValueError:
        await bot.send_message(chat_id, _("⚠️ Type correct number (like 125.5)"))


@bot.message_handler(func=lambda message: user_states.get(message.chat.id) == 'waiting_for_traditional_end')
async def handle_traditional_end(message):
    chat_id = message.chat.id
    try:
        end_counter = float("".join(filter(lambda x: x.isdigit() or x == '.', message.text)))

        if chat_id not in user_irrigation_data:
            await bot.send_message(chat_id, _("❌ Your data was not found in the system"))
            return

        start_counter = user_irrigation_data[chat_id]['start_counter']

        if start_counter > end_counter:
            await bot.send_message(chat_id, _("⚠️ Error: start value is greater than end value!"))
            return

        used_m3 = end_counter - start_counter

        # Сохраняем в БД (аналогично counter)
        row = await get_irrigation_data(chat_id)
        if row is not None:
            area = float(row['area'])
            actual_mm = (used_m3 * float(row['ie'])) / (10 * area * float(row['wa']))

            query = """
                UPDATE WWCServices.Irrigation SET irrigationApp = :actual_mm
                WHERE siteID = :siteID AND date = DATE_SUB(CURDATE(), INTERVAL 1 DAY)
            """
            values = {'actual_mm': actual_mm, 'siteID': row['siteID']}
            await database.execute(query=query, values=values)

            await bot.send_message(
                chat_id,
                _("✅ Data saved!\n"
                  "Water used: {used_m3:.2f} m³\n"
                  "Equivalent to: {actual_mm:.2f} mm"
                  ).format(used_m3=used_m3, actual_mm=actual_mm)
            )

    except ValueError:
        await bot.send_message(chat_id, _("⚠️ Type correct number (like 125.5)"))

    finally:
        # Очищаем состояние
        user_states[chat_id] = None
        if chat_id in user_irrigation_data:
            del user_irrigation_data[chat_id]


@bot.message_handler(func=lambda message: user_states.get(message.chat.id) == 'waiting_for_counter_end')
async def handle_counter_end(message):
    chat_id = message.chat.id
    try:
        end_counter = float("".join(filter(lambda x: x.isdigit() or x == '.', message.text)))

        if chat_id not in user_irrigation_data or 'start_counter' not in user_irrigation_data[chat_id]:
            await bot.send_message(chat_id, _("❌ Error: No start data found"))
            return

        start_counter = user_irrigation_data[chat_id]['start_counter']
        if start_counter > end_counter:
            await bot.send_message(
                chat_id,
                _("⚠️ Error: The initial value of the counter cannot be greater than the final value!\n"
                  "Please enter correct data.")
            )
            return

        used_m3 = round(end_counter - start_counter, 2)

        row = await get_irrigation_data(chat_id)  # ✅ Важно: get_irrigation_data должна быть функцией!
        if row is not None:
            area = float(row['area'])
            actual_mm = (used_m3 * float(row['ie'])) / (10 * area * float(row['wa']))

            query = """
                UPDATE WWCServices.Irrigation SET irrigationApp = :actual_mm
                WHERE siteID = :siteID AND date = DATE_SUB(CURDATE(), INTERVAL 1 DAY)
            """
            values = {'actual_mm': actual_mm, 'siteID': row['siteID']}
            await database.execute(query=query, values=values)

            await bot.send_message(
                chat_id,
                _("✅ Data saved!\n"
                  "Water used: {used_m3:.2f} m³\n"
                  "Equivalent to: {actual_mm:.2f} mm"
                  ).format(
                    used_m3=used_m3,
                    equivalent_mm=actual_mm
                )
            )
    except ValueError:
        await bot.send_message(chat_id, _("⚠️ Type correct number (like 125.5)"))
    finally:
        user_states[chat_id] = None
        if chat_id in user_irrigation_data:
            del user_irrigation_data[chat_id]


@bot.message_handler(func=lambda message: user_states.get(message.chat.id) == 'waiting_for_actual_data')
async def handle_actual_data(message):
    chat_id = message.chat.id
    try:
        actual_m3 = float("".join(filter(lambda x: x.isdigit() or x == '.', message.text)))
        row = await get_irrigation_data(chat_id)
        if row is not None:
            area = float(row['area'])
            actual_mm = (actual_m3 * float(row['ie'])) / (10 * area * float(row['wa']))

            query = """
                UPDATE WWCServices.Irrigation SET irrigationApp = :actual_mm
                WHERE siteID = :siteID AND date = DATE_SUB(CURDATE(), INTERVAL 1 DAY)
            """
            values = {'actual_mm': actual_mm, 'siteID': row['siteID']}
            await database.execute(query=query, values=values)

            await bot.send_message(
                chat_id,
                _(
                    "✅ Data saved!\n"
                    "Water used: {used_m3:.2f} m³\n"
                    "Equivalent to: {actual_mm:.2f} mm"
                ).format(
                    used_m3=actual_m3,
                    equivalent_mm=actual_mm
                )
            )
    except ValueError:
        await bot.send_message(chat_id, _("⚠️ Please enter a valid number (e.g. 150 or 75.5)"))
    finally:
        user_states[chat_id] = None


async def send_recommendation(chat_id, fieldtype, irrigation_need, area, ie, wa, water_level=None):
    try:
        if fieldtype == 'channel' and water_level is not None:
            calculation = await calculate_irrigation(chat_id, water_level, irrigation_need, area, ie, wa)

            if calculation['is_completed']:
                msg = _("✅ Irrigation completed! Enough water.")
            else:
                hours = int(calculation['remaining_time'])
                minutes = int((calculation['remaining_time'] - hours) * 60)

                msg = _(
                    "💦 Current level: {water_level} cm\n"
                    "⏱ Time left: {hours}h {minutes}m\n"
                    "📊 Used: {used_m3:.2f} m³ of {total_m3:.2f} m³"
                ).format(
                    water_level=water_level,
                    hours=hours,
                    minutes=minutes,
                    used_m3=calculation['used_m3'],
                    total_m3=calculation['used_m3'] + calculation['remaining_m3']
                )
        elif fieldtype in ['pump', 'counter']:
            m3_need = (irrigation_need * 10 * area * wa) / ie
            msg = f"🔢 Required: {round(m3_need, 2)} m³ water"
        else:
            msg = _("❌ Unsupported field type")

        await bot.send_message(chat_id, msg)
    except (ValueError, TypeError):
        await bot.send_message(chat_id, _("⚠️ Input data error"))


async def main():
    await database.connect()

    # Clearing old tasks on startup
    # XXX Do we need this? It's AsyncIOScheduler so jobs should not persist
    scheduler.remove_all_jobs()

    # Check irrigation for all users, every day at 7 am
    scheduler.add_job(check_all_users, 'cron', hour=7, minute=0, timezone=TIMEZONE)
    scheduler.start()

    # Start bot
    try:
        await bot.polling()
    finally:
        scheduler.shutdown()
        await database.disconnect()


if __name__ == "__main__":
    asyncio.run(main())
