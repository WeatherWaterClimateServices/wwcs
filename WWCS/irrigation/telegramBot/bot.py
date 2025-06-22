from datetime import datetime, timedelta
import asyncio
import gettext
import os
import pathlib
import traceback

# Requirements
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.interval import IntervalTrigger
from telebot import types
from telebot.async_telebot import AsyncTeleBot
import pymysql

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
bot = AsyncTeleBot("YOUR_TOKEN")
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
        user="root",
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
    FROM SitesHumans.Sites s
        JOIN SitesHumans.Humans h ON JSON_UNQUOTE(JSON_EXTRACT(s.fieldproperties, '$.humanID')) = h.humanID
        JOIN WWCServices.Irrigation i ON i.siteID = s.siteID
    WHERE s.irrigation = 1 AND i.PHIc < i.PHIt AND i.irrigationApp = 0
    AND i.date = DATE_SUB(CURDATE(), INTERVAL 1 DAY)
    """
    rows = await execute_query(query)
    print(f"[DEBUG] Запрос к БД выполнен. Найдено записей: {len(rows)}")
    for row in rows:
        print(f"[DEBUG] telegramID: {row['telegramID']}, type: {row['type']}, siteID: {row['siteID']}")
    return rows



BUTTONS = {
    "send_recommendation": "Send recommendation",
    "no_water": "No water",
    "save_data": "Save data"
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


async def start_irrigation_notifications(chat_id):
    await notification_manager.add_job(
        chat_id,
        'water_check',
        send_water_check_notification,
        trigger=IntervalTrigger(minutes=15),
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
            "🔄 Please check the current water level in the channel and send its value"
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
            "⏰ Watering time is over! Please click the 'Save data' button to save the results."
        )
        await notification_manager.remove_job(chat_id, 'water_check')


async def check_irrigation(chat_id):
    rows = await get_irrigation_data()
    for row in rows:
        if str(chat_id) == str(row['telegramID']) and row['irrigation'] == 1:
            markup = create_reply_keyboard()
            m3_needed = (float(row['irrigationNeed']) * 10 * float(row['area']) * float(row['wa'])) / float(row['ie'])

            if row['type'] == "channel":
                text = (
                    "🌤 Good morning, {first_name}!\n"
                    "Your plot is ready for irrigation.\n"
                    "💧 Water required: {water:.2f} m³"
                )

            elif row['type'] == "counter":
                text = (
                    "🌤 Good morning, {first_name}!\n"
                    "Your plot is ready for irrigation.\n"
                    "💧 Water required: {water:.2f} m³"
                )

            elif row['type'] == "traditional":
                text = (
                    "Hello, {first_name}!\n"
                    "If your irrigation complete please push Save data button and enter you counter numbers Before and After irrigation\n"
                    "and save your data"
                )

            else:
                text = (
                    "ERROR!"
                )

            await bot.send_message(
                chat_id,
                text.format(first_name=row['firstName'], water=round(m3_needed, 2)),
                reply_markup=markup
            )
            print(f"[DEBUG] Проверка полива для chat_id: {chat_id}")
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
    total_needed_m3 = (irrigation_need * area * 10 * wa) / ie

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


@bot.message_handler(func=lambda message: message.text == BUTTONS["send_recommendation"])
async def handle_recommendation(message):
    chat_id = message.chat.id
    rows = await get_irrigation_data()
    for row in rows:
        if str(chat_id) == str(row['telegramID']):
            if row['type'] == "channel":
                user_states[chat_id] = "waiting_for_water_level"
                await bot.send_message (chat_id, "Enter the current water level in the channel (in cm):")

            elif row['type'] == "counter":
                user_states[chat_id] = "waiting_for_counter_start"
                await bot.send_message(chat_id, "Please, send the counter value before irrigation (m³):")

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
    await bot.send_message(chat_id, "❌ Your data was not found in the system")



@bot.message_handler(func=lambda message: user_states.get(message.chat.id) == 'waiting_for_counter_start')
async def handle_counter_start(message):
    chat_id = message.chat.id
    try:
        start_counter = float("".join(filter(lambda x: x.isdigit() or x == '.', message.text)))

        rows = await get_irrigation_data()
        for row in rows:
            if str(chat_id) == str(row['telegramID']):
                m3_needed = (float(row['irrigationNeed']) * 10 * float(row['area'])) * float(row['wa']) / float(row['ie'])
                target_counter = start_counter + m3_needed

                await bot.send_message(
                    chat_id,
                     "Irrigate untill you counter is: {target_counter:.2f} m³\n"
                    "Water need: {m3_needed:.2f} m³"

                )

                # Сохраняем начальные показания для последующего расчета
                user_irrigation_data[chat_id] = {
                    'start_counter': start_counter,
                    'target_counter': target_counter,
                    'is_active': True,
                    'last_update': datetime.now()
                }
                user_states[chat_id] = None
                return
        await bot.send_message(chat_id, "❌ Your data was not found in the system")
    except ValueError:
        await bot.send_message(chat_id, "⚠️ Please, type number (125.5)")


@bot.message_handler(func=lambda message: user_states.get(message.chat.id) == 'waiting_for_water_level')
async def handle_water_level(message):
    chat_id = message.chat.id
    try:
        water_level = float("".join(filter(lambda x: x.isdigit() or x == '.', message.text)))

        # Проверяем что уровень воды в допустимом диапазоне
        if water_level < 1 or water_level > 25:
            await bot.send_message(
                chat_id,
                "⚠️ Incorrect water level! Acceptable values from 1 to 25 cm.\n"
                "Please enter the correct value:"
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
                    msg = "✅ Irrigation completed! Enough water."
                else:
                    hours = int(calculation['remaining_time'])
                    minutes = int((calculation['remaining_time'] - hours) * 60)

                    msg = (
                        "💦 Current level: {water_level} cm\n"
                        "⏱ Time left: {hours}h {minutes}m\n"
                        "📊 Used: {used_m3:.2f} m³ of {total_m3:.2f} m³"
                    )

                await bot.send_message(chat_id, msg)
                user_states[chat_id] = None
                return
        await bot.send_message(chat_id, "❌ Your data was not found in the system")
    except ValueError:
        await bot.send_message(chat_id, "⚠️ Please enter a valid number (water level in cm)")


@bot.message_handler(func=lambda message: message.text == BUTTONS["save_data"])
async def handle_send_data(message):
    chat_id = message.chat.id
    print(f"[SAVE_DATA_HANDLER] chat_id: {chat_id}")

    # Останавливаем все уведомления
    await notification_manager.remove_all_jobs(chat_id)
    print(f"[SAVE_DATA_NOTIFICATIONS] Notifications stopped for chat_id: {chat_id}")

    rows = await get_irrigation_data()
    print(f"[SAVE_DATA_DB_QUERY] Found {len(rows)} rows for chat_id: {chat_id}")

    for row in rows:
        if str(chat_id) == str(row['telegramID']):
            print(f"[SAVE_DATA_FOUND] Found record for chat_id: {chat_id}, type: {row['type']}")

            if row['type'] == "counter":
                if chat_id in user_irrigation_data and 'start_counter' in user_irrigation_data[chat_id]:
                    print("[SAVE_DATA_COUNTER] Requesting end counter value")
                    await bot.send_message(chat_id, "Please send your counter number AFTER irrigation (m³):")
                    user_states[chat_id] = "waiting_for_counter_end"
                else:
                    print("[SAVE_DATA_COUNTER] Requesting start counter value")
                    await bot.send_message(chat_id, "Please send your counter number BEFORE irrigation (m³):")
                    user_states[chat_id] = "waiting_for_counter_start"
                return

            elif row['type'] == "traditional":
                print("[SAVE_DATA_TRADITIONAL] Requesting start counter value")
                await bot.send_message(chat_id, "Please send your counter number BEFORE irrigation (m³):")
                user_states[chat_id] = "waiting_for_traditional_start"
                return

            elif row['type'] == "channel":
                if chat_id in user_irrigation_data and user_irrigation_data[chat_id].get('is_active', False):
                    try:
                        data = user_irrigation_data[chat_id]
                        time_elapsed = (datetime.now() - data['last_update']).total_seconds()
                        flow_rate = WATER_FLOW_RATES.get(data['current_level'], 0)
                        additional_used = flow_rate * (time_elapsed / 60)
                        used_m3 = data['total_used_m3'] + additional_used

                        print(f"[SAVE_DATA_CHANNEL] used_m3: {used_m3} (flow_rate: {flow_rate}, time_elapsed: {time_elapsed}s)")

                        # Используем универсальную функцию сохранения
                        success, message_text = await save_irrigation_data(chat_id, used_m3, row['siteID'])
                        await bot.send_message(chat_id, message_text)

                        data['is_active'] = False
                        print(f"[SAVE_DATA_CHANNEL] Irrigation marked as inactive for chat_id: {chat_id}")
                    except Exception as e:
                        error_msg = f"⚠️ Error saving data: {str(e)}"
                        print(f"[SAVE_DATA_CHANNEL_ERROR] {error_msg}")
                        await bot.send_message(chat_id, error_msg)
                else:
                    error_msg = "❌ No active irrigation session found"
                    print(f"[SAVE_DATA_CHANNEL_ERROR] {error_msg}")
                    await bot.send_message(chat_id, error_msg)
                return

    error_msg = "❌ Your data was not found in the system"
    print(f"[SAVE_DATA_ERROR] {error_msg}")
    await bot.send_message(chat_id, error_msg)




@bot.message_handler(func=lambda message: user_states.get(message.chat.id) == 'waiting_for_traditional_start')
async def handle_traditional_start(message):
    chat_id = message.chat.id
    try:
        start_counter = float("".join(filter(lambda x: x.isdigit() or x == '.', message.text)))
        print(f"[TRADITIONAL_START] chat_id: {chat_id}, start_counter: {start_counter}")

        user_irrigation_data[chat_id] = {
            'start_counter': start_counter,
            'type': "traditional"
        }

        await bot.send_message(chat_id, "Now send counter value AFTER irrigation (m³)")
        user_states[chat_id] = "waiting_for_traditional_end"
    except ValueError:
        error_msg = "⚠️ Type correct number (like 125.5)"
        print(f"[TRADITIONAL_START_ERROR] {error_msg}")
        await bot.send_message(chat_id, error_msg)




@bot.message_handler(func=lambda message: user_states.get(message.chat.id) == 'waiting_for_traditional_end')
async def handle_traditional_end(message):
    chat_id = message.chat.id
    try:
        end_counter = float("".join(filter(lambda x: x.isdigit() or x == '.', message.text)))
        print(f"[TRADITIONAL_END] chat_id: {chat_id}, end_counter: {end_counter}")

        if chat_id not in user_irrigation_data:
            error_msg = "❌ No irrigation data found. Please start over."
            print(f"[TRADITIONAL_END_ERROR] {error_msg}")
            await bot.send_message(chat_id, error_msg)
            user_states[chat_id] = None
            return

        start_counter = user_irrigation_data[chat_id]['start_counter']
        if start_counter > end_counter:
            error_msg = "⚠️ Error: Start value cannot be greater than end value!"
            print(f"[TRADITIONAL_END_ERROR] {error_msg}")
            await bot.send_message(chat_id, error_msg)
            return

        used_m3 = end_counter - start_counter
        print(f"[TRADITIONAL_CALC] used_m3: {used_m3} (start: {start_counter}, end: {end_counter})")

        # Используем универсальную функцию сохранения
        success, message_text = await save_irrigation_data(chat_id, used_m3)
        await bot.send_message(chat_id, message_text)

    except ValueError:
        error_msg = "⚠️ Please enter a valid number (e.g. 125.5)"
        print(f"[TRADITIONAL_END_ERROR] {error_msg}")
        await bot.send_message(chat_id, error_msg)
    finally:
        print(f"[TRADITIONAL_CLEANUP] Clearing state for chat_id: {chat_id}")
        user_states[chat_id] = None
        if chat_id in user_irrigation_data:
            del user_irrigation_data[chat_id]


@bot.message_handler(func=lambda message: user_states.get(message.chat.id) == 'waiting_for_counter_end')
async def handle_counter_end(message):
    chat_id = message.chat.id
    try:
        end_counter = float("".join(filter(lambda x: x.isdigit() or x == '.', message.text)))
        print(f"[COUNTER_END] chat_id: {chat_id}, end_counter: {end_counter}")

        if chat_id not in user_irrigation_data or 'start_counter' not in user_irrigation_data[chat_id]:
            error_msg = "❌ Error: No start data found. Please start over."
            print(f"[COUNTER_END_ERROR] {error_msg}")
            await bot.send_message(chat_id, error_msg)
            user_states[chat_id] = None
            return

        start_counter = user_irrigation_data[chat_id]['start_counter']
        if start_counter > end_counter:
            error_msg = "⚠️ Error: Start value cannot be greater than end value!"
            print(f"[COUNTER_END_ERROR] {error_msg}")
            await bot.send_message(chat_id, error_msg)
            return

        used_m3 = end_counter - start_counter
        print(f"[COUNTER_CALC] used_m3: {used_m3} (start: {start_counter}, end: {end_counter})")

        # Используем универсальную функцию сохранения
        success, message_text = await save_irrigation_data(chat_id, used_m3)
        await bot.send_message(chat_id, message_text)

    except ValueError:
        error_msg = "⚠️ Please enter a valid number (e.g. 125.5)"
        print(f"[COUNTER_END_ERROR] {error_msg}")
        await bot.send_message(chat_id, error_msg)
    finally:
        print(f"[COUNTER_CLEANUP] Clearing state for chat_id: {chat_id}")
        user_states[chat_id] = None
        if chat_id in user_irrigation_data:
            del user_irrigation_data[chat_id]



@bot.message_handler(func=lambda message: user_states.get(message.chat.id) == 'waiting_for_actual_data')
async def handle_actual_data(message):
    chat_id = message.chat.id
    try:
        actual_m3 = float("".join(filter(lambda x: x.isdigit() or x == '.', message.text)))
        rows = await get_irrigation_data()

        for row in rows:
            if str(chat_id) == str(row['telegramID']):
                area = float(row['area'])
                actual_mm = (actual_m3 * float(row['ie'])) / (10 * area * float(row['wa']))

                await execute_query(
                    """UPDATE WWCServices.Irrigation 
                    SET irrigationApp = %s 
                    WHERE siteID = %s 
                    AND date = DATE_SUB(CURDATE(), INTERVAL 1 DAY)""",
                    (actual_mm, row['siteID'])
                )

                await bot.send_message(
                    chat_id,

                    "✅ Data saved!\n"
                    "Water used: {used_m3:.2f} m³\n"
                    "Equivalent to: {actual_mm:.2f} mm"

                )
                break
        else:
            await bot.send_message(chat_id, "❌ Your data was not found in the system")
    except ValueError:
        await bot.send_message(chat_id, "⚠️ Please enter a valid number (e.g. 150 or 75.5)")
    finally:
        user_states[chat_id] = None


async def send_recommendation(chat_id, fieldtype, irrigation_need, area, ie, wa, water_level=None):
    try:
        if fieldtype == 'channel' and water_level is not None:
            calculation = await calculate_irrigation(chat_id, water_level, irrigation_need, area, ie, wa)

            if calculation['is_completed']:
                msg = "✅ Irrigation completed! Enough water."
            else:
                hours = int(calculation['remaining_time'])
                minutes = int((calculation['remaining_time'] - hours) * 60)

                msg = (
                    "💦 Current level: {water_level} cm\n"
                    "⏱ Time left: {hours}h {minutes}m\n"
                    "📊 Used: {used_m3:.2f} m³ of {total_m3:.2f} m³"
                )
        elif fieldtype in ['pump', 'counter']:
            m3_need = (irrigation_need * 10 * area * wa) / ie
            msg = f"🔢 Required: {round(m3_need, 2)} m³ water"
        else:
            msg = "❌ Unsupported field type"

        await bot.send_message(chat_id, msg)
    except (ValueError, TypeError):
        await bot.send_message(chat_id, "⚠️ Input data error")



async def save_irrigation_data(chat_id, used_m3, site_id=None):
    try:
        print(f"[SAVE_DATA_START] chat_id: {chat_id}, used_m3: {used_m3}, site_id: {site_id or 'not provided'}")

        if not site_id:
            rows = await get_irrigation_data()
            print(f"[SAVE_DATA_DEBUG] Found {len(rows)} rows for chat_id: {chat_id}")

            for row in rows:
                if str(chat_id) == str(row['telegramID']):
                    site_id = row['siteID']
                    print(f"[SAVE_DATA_DEBUG] Found site_id: {site_id} for chat_id: {chat_id}")
                    break
            else:
                error_msg = "❌ Your data was not found in the system"
                print(f"[SAVE_DATA_ERROR] {error_msg}")
                return False, error_msg

        query = """
        SELECT 
            JSON_EXTRACT(fieldproperties, '$.area') AS area,
            JSON_EXTRACT(fieldproperties, '$.IE') AS ie,
            JSON_EXTRACT(fieldproperties, '$.WA') AS wa
        FROM Sites
        WHERE siteID = %s
        """
        print(f"[SAVE_DATA_QUERY] Executing query for site_id: {site_id}")

        result = await execute_query(query, (site_id,))
        if not result:
            error_msg = f"❌ Site configuration not found for site_id: {site_id}"
            print(f"[SAVE_DATA_ERROR] {error_msg}")
            return False, error_msg

        row = result[0]
        print(f"[SAVE_DATA_DEBUG] Site params: {row}")

        area = float(row['area'])
        ie = float(row['ie'])
        wa = float(row['wa'])

        actual_mm = (used_m3 * ie) / (10 * area * wa)
        print(f"[SAVE_DATA_CALC] used_m3: {used_m3} -> actual_mm: {actual_mm}")

        update_query = """
        UPDATE WWCServices.Irrigation 
        SET irrigationApp = %s 
        WHERE siteID = %s 
        AND date = DATE_SUB(CURDATE(), INTERVAL 1 DAY)
        """
        print(f"[SAVE_DATA_UPDATE] Executing update: {update_query} with params: ({actual_mm}, {site_id})")

        await execute_query(update_query, (actual_mm, site_id))

        success_msg = f"✅ Data saved!\nWater used: {used_m3:.2f} m³\nEquivalent to: {actual_mm:.2f} mm"
        print(f"[SAVE_DATA_SUCCESS] {success_msg}")
        return True, success_msg

    except Exception as e:
        error_msg = f"⚠️ Error saving data: {str(e)}"
        print(f"[SAVE_DATA_EXCEPTION] {error_msg}\nTraceback: {traceback.format_exc()}")
        return False, error_msg

async def main():
    # Очищаем старые задания при запуске
    for job in scheduler.get_jobs():
        job.remove()

    scheduler.add_job(
        check_all_users,
        'cron',
        hour=datetime.now().hour,
        minute=datetime.now().minute +1,  # Через 1 минуту от текущего времени
        timezone='Asia/Tashkent'
    )
    scheduler.start()

    try:
        await bot.polling()
    finally:
        scheduler.shutdown()


if __name__ == "__main__":
    asyncio.run(main())
