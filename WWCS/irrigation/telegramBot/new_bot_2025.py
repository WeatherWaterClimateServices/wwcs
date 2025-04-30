from telebot.async_telebot import AsyncTeleBot
from telebot import types
import pymysql
import asyncio
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.interval import IntervalTrigger
from apscheduler.triggers.date import DateTrigger
from datetime import datetime, timedelta
import gettext
import pathlib

# Initialize gettext
root = pathlib.Path(__file__).parent
translation = gettext.translation(
    'messages',                 # The domain, messages is the default
    localedir=root / 'locale',  # Where the translation files are stored
    languages=[LANGUAGE],       # We only support one language at a time
    fallback=True,              # Return the source id if not translation file is found
)
_ = translation.gettext


class NotificationManager:
    def __init__(self):
        self.jobs = {}

    async def add_job(self, chat_id, job_type, func, *args, **kwargs):
        await self.remove_job(chat_id, job_type)
        job = scheduler.add_job(func, *args, **kwargs)
        self.jobs[f"{job_type}_{chat_id}"] = job
        return job

    async def remove_job(self, chat_id, job_type):
        job_id = f"{job_type}_{chat_id}"
        if job_id in self.jobs:
            try:
                self.jobs[job_id].remove()
            except Exception as e:
                print (f"Error deleting task {job_id}: {e}")
            finally:
                self.jobs.pop(job_id, None)

    async def remove_all_jobs(self, chat_id):
        for job_type in ['water_check', 'polyv_complete']:
            await self.remove_job(chat_id, job_type)


notification_manager = NotificationManager()




# Инициализация бота
bot = AsyncTeleBot("TOKEN")
scheduler = AsyncIOScheduler()

# Словари для хранения состояний
user_states = {}
user_irrigation_data = {}  # Для хранения данных о поливе
notification_jobs = {}  # Для хранения задач уведомлений

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
    25: 2.63
}


# Подключение к базе данных MySQL
def get_db_connection():
    return pymysql.connect(
        host="localhost",
        user="user",
        password="password",
        db="db",
        cursorclass=pymysql.cursors.DictCursor
    )


async def execute_query(query, params=None):
    def sync_execute():
        connection = get_db_connection()
        try:
            with connection.cursor() as cursor:
                cursor.execute(query, params or ())
                result = cursor.fetchall()
                connection.commit()
                return result
        finally:
            connection.close()

    return await asyncio.to_thread(sync_execute)


async def get_irrigation_data():
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
    FROM Sites s
        JOIN Humans h ON JSON_UNQUOTE(JSON_EXTRACT(s.fieldproperties, '$.humanID')) = h.humanID
        JOIN WWCServices.Irrigation i ON i.siteID = s.siteID
    WHERE s.irrigation = 1 AND i.PHIc < i.PHIt AND i.irrigationApp = 0
    AND i.date = DATE_SUB(CURDATE(), INTERVAL 1 DAY)
    """
    return await execute_query(query)


def create_reply_keyboard():
    markup = types.ReplyKeyboardMarkup(row_width=2, resize_keyboard=True)
    buttons = [
        types.KeyboardButton('Send recommendation'),
        types.KeyboardButton('No water'),
        types.KeyboardButton('Save data')
    ]
    markup.add(*buttons)
    return markup


async def start_irrigation_notifications(chat_id):
    await notification_manager.add_job(
        chat_id,
        'water_check',
        send_water_check_notification,
        trigger=IntervalTrigger(minutes=5),
        args=[chat_id]
    )


async def stop_irrigation_notifications(chat_id):
    """Останавливает уведомления для указанного чата"""
    job_id = f'water_check_{chat_id}'
    try:
        if job_id in notification_jobs:
            job = notification_jobs[job_id]
            job.remove()
            del notification_jobs[job_id]
    except Exception as e:
        print(f"Error deleting task: {e}")



async def send_water_check_notification(chat_id):
    """Отправляет уведомление о проверке уровня воды"""
    if chat_id in user_irrigation_data:
        await bot.send_message(
            chat_id,
            _("🔄 Please check the current water level in the channel and send its value")
        )


async def schedule_polyv_completion_notification(chat_id, hours, minutes):
    completion_time = datetime.now() + timedelta(hours=hours, minutes=minutes)
    await notification_manager.add_job(
        chat_id,
        'polyv_complete',
        notify_polyv_completion,
        trigger='date',
        run_date=completion_time,
        args=[chat_id]
    )



async def stop_polyv_completion_notification(chat_id):
    """Останавливает уведомление о завершении полива"""
    job_id = f'polyv_complete_{chat_id}'
    try:
        if job_id in notification_jobs:
            job = notification_jobs[job_id]
            job.remove()
            del notification_jobs[job_id]
    except Exception as e:
        print(f"Error deleting task: {e}")  # Логируем ошибку, но не прерываем выполнение



async def notify_polyv_completion(chat_id):
    if chat_id in user_irrigation_data and user_irrigation_data[chat_id].get('is_active', False):
        await bot.send_message(
            chat_id,
            _("⏰ Watering time is over! Please click the 'Save data' button to save the results.")
        )
        await notification_manager.remove_job(chat_id, 'water_check')


async def check_irrigation(chat_id):
    rows = await get_irrigation_data()
    for row in rows:
        if str(chat_id) == str(row['telegramID']) and row['irrigation'] == 1:
            markup = create_reply_keyboard()
            m3_needed = (float(row['irrigationNeed']) * 10 * float(row['area']) * float(row['ie'])) / float(row['wa'])
            # await bot.send_message(
            #     chat_id,
            #     f"🌤 Good morning, {row['firstName']}!\n"
            #     f"Your plot is ready for irrigation.\n"
            #     f"💧 Water required: {round(m3_needed, 2)} m³",
            #
            #     reply_markup=markup
            # )

            text = _(
                "🌤 Good morning, {first_name}!\n"
                "Your plot is ready for irrigation.\n"
                "💧 Water required: {water:.2f} m³"
            )
            await bot.send_message(
                chat_id,
                text.format(first_name=row['firstName'], water=round(m3_needed, 2)),
                reply_markup=markup
            )
            return True
    return False


async def check_all_users():
    rows = await get_irrigation_data()
    notified_users = set()
    for row in rows:
        if row['irrigation'] == 1 and row['telegramID'] not in notified_users:
            chat_id = row['telegramID']
            try:
                await check_irrigation(chat_id)
                notified_users.add(chat_id)
            except Exception as e:
                print(f"Notification error for {chat_id}: {e}")


async def calculate_irrigation(chat_id, water_level, irrigation_need, area, ie, wa):
    total_needed_m3 = (irrigation_need * area * 10 * ie) / wa

    if chat_id not in user_irrigation_data:
        user_irrigation_data[chat_id] = {
            'start_time': datetime.now(),
            'last_update': datetime.now(),
            'current_level': water_level,
            'total_needed_m3': total_needed_m3,
            'total_used_m3': 0,
            'history': [(water_level, datetime.now())],
            'is_active': True
        }

        # Запускаем уведомления только для нового полива
        await start_irrigation_notifications(chat_id)
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
        await schedule_polyv_completion_notification(chat_id, hours, minutes)

    return {
        'used_m3': user_irrigation_data[chat_id]['total_used_m3'],
        'remaining_m3': remaining_m3,
        'remaining_time': remaining_time,
        'is_completed': remaining_m3 <= 0
    }


@bot.message_handler(commands=['start'])
async def start(message):
    markup = create_reply_keyboard()
    await bot.send_message(message.chat.id, "Select action:", reply_markup=markup)
    await check_irrigation(message.chat.id)


@bot.message_handler(func=lambda message: message.text == 'Send recommendation')
async def handle_recommendation(message):
    chat_id = message.chat.id
    rows = await get_irrigation_data()
    for row in rows:
        if str(chat_id) == str(row['telegramID']):
            if row['type'] == "channel":
                user_states[chat_id] = "waiting_for_water_level"
                await bot.send_message (chat_id, _("Enter the current water level in the channel (in cm):"))
            else:
                await send_recommendation(
                    chat_id,
                    row['type'],
                    float(row['irrigationNeed']),
                    float(row['area']),
                    float(row['ie']),
                    float(row['wa'])
                )
            return
    await bot.send_message(chat_id, _("❌ Your data was not found in the system"))


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

        rows = await get_irrigation_data()
        for row in rows:
            if str(chat_id) == str(row['telegramID']):
                calculation = await calculate_irrigation(
                    chat_id,
                    water_level,
                    float(row['irrigationNeed']),
                    float(row['area']),
                    float(row['ie']),
                    float(row['wa'])
                )

                if calculation['is_completed']:
                    msg = _("✅ Irrigation completed! Enough water.")
                else:
                    hours = int(calculation['remaining_time'])
                    minutes = int((calculation['remaining_time'] - hours) * 60)
                    # msg = (
                    #     f"💦 Current level: {water_level} cm\n"
                    #     f"⏱ Time left: {hours}h {minutes}m\n"
                    #     f"📊 Used: {round(calculation['used_m3'], 2)} m³ of {round(calculation['used_m3'] + calculation['remaining_m3'], 2)} m³"
                    # )

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

                await bot.send_message(chat_id, msg)
                user_states[chat_id] = None
                return
        await bot.send_message(chat_id, _("❌ Your data was not found in the system"))
    except ValueError:
        await bot.send_message(chat_id, _("⚠️ Please enter a valid number (water level in cm)"))



@bot.message_handler(func=lambda message: message.text == 'Save data')
async def handle_send_data(message):
    chat_id = message.chat.id

    # Гарантированно останавливаем все уведомления
    await notification_manager.remove_all_jobs(chat_id)

    if chat_id in user_irrigation_data and user_irrigation_data[chat_id].get('is_active', False):
        try:
            data = user_irrigation_data[chat_id]
            time_elapsed = (datetime.now() - data['last_update']).total_seconds()
            flow_rate = WATER_FLOW_RATES.get(data['current_level'], 0)
            additional_used = flow_rate * (time_elapsed / 60)
            data['total_used_m3'] += additional_used

            rows = await get_irrigation_data()
            for row in rows:
                if str(chat_id) == str(row['telegramID']):
                    area = float(row['area'])
                    actual_mm = (data['total_used_m3'] * float(row['wa'])) / (10 * area * float(row['ie']))

                    await execute_query(
                        """UPDATE WWCServices.Irrigation 
                        SET irrigationApp = %s 
                        WHERE siteID = %s 
                        AND date = DATE_SUB(CURDATE(), INTERVAL 1 DAY)""",
                        (actual_mm, row['siteID'])
                    )

                    # await bot.send_message(
                    #     chat_id,
                    #     f"✅ Data saved! Used: {round(data['total_used_m3'], 2)} m³"
                    # )

                    await bot.send_message(
                        chat_id,
                        _(
                            "✅ Data saved! Used: {used_m3:.2f} m³"
                        ).format(
                            used_m3=data['total_used_m3']
                        )
                    )
                    data['is_active'] = False
                    return

            await bot.send_message(chat_id, _("❌ Your data was not found in the system"))
        except Exception as e:
            print(f"Error while saving: {str(e)}")
            await bot.send_message(chat_id, _("⚠️ Error saving data"))
    else:
        await bot.send_message(chat_id, _("Enter actual water consumption (m³):"))
        user_states[chat_id] = "waiting_for_actual_data"


@bot.message_handler(func=lambda message: user_states.get(message.chat.id) == 'waiting_for_actual_data')
async def handle_actual_data(message):
    chat_id = message.chat.id
    try:
        actual_m3 = float("".join(filter(lambda x: x.isdigit() or x == '.', message.text)))
        rows = await get_irrigation_data()

        for row in rows:
            if str(chat_id) == str(row['telegramID']):
                area = float(row['area'])
                actual_mm = (actual_m3 * float(row['wa'])) / (10 * area * float(row['ie']))

                await execute_query(
                    """UPDATE WWCServices.Irrigation 
                    SET irrigationApp = %s 
                    WHERE siteID = %s 
                    AND date = DATE_SUB(CURDATE(), INTERVAL 1 DAY)""",
                    (actual_mm, row['siteID'])
                )

                # await bot.send_message(
                #     chat_id,
                #     f"✅ Data saved!\n"
                #     f"Water used: {round(actual_m3, 2)} m³\n"
                #     f"Equivalent to: {round(actual_mm, 2)} mm"
                # )

                await bot.send_message(
                    chat_id,
                    _(
                        "✅ Data saved!\n"
                        "Water used: {used_m3:.2f} m³\n"
                        "Equivalent to: {equivalent_mm:.2f} mm"
                    ).format(
                        used_m3=actual_m3,
                        equivalent_mm=actual_mm
                    )
                )
                break
        else:
            await bot.send_message(chat_id, _("❌ Your data was not found in the system"))
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
                # msg = (
                #     f"💦 Current level: {water_level} cm\n"
                #     f"⏱ Time left: {hours}h {minutes}m\n"
                #     f"📊 Used: {round(calculation['used_m3'], 2)} m³ of {round(calculation['used_m3'] + calculation['remaining_m3'], 2)} m³"
                # )

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
            m3_need = (irrigation_need * 10 * area * ie) / wa
            msg = f"🔢 Required: {round(m3_need, 2)} m³ water"
        else:
            msg = _("❌ Unsupported field type")

        await bot.send_message(chat_id, msg)
    except (ValueError, TypeError):
        await bot.send_message(chat_id, _("⚠️ Input data error"))


async def main():
    # Очищаем старые задания при запуске
    for job in scheduler.get_jobs():
        job.remove()

    scheduler.add_job(
        check_all_users,
        'cron',
        hour=datetime.now().hour,
        minute=datetime.now().minute + 1,  # Через 1 минуту от текущего времени
        timezone='Asia/Tashkent'
    )
    scheduler.start()

    try:
        await bot.polling()
    finally:
        scheduler.shutdown()


if __name__ == "__main__":
    asyncio.run(main())
