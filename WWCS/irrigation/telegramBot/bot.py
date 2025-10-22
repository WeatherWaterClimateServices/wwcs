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
import traceback

# Configuration
dotenv.load_dotenv()
DB_USERNAME = os.environ.get('DB_USERNAME', 'root')
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
    'messages',  # The domain, messages is the default
    localedir=root / 'locale',  # Where the translation files are stored
    languages=[LANGUAGE],  # We only support one language at a time
    fallback=True,  # Return the source id if not translation file is found
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

# Bot initialization
bot = AsyncTeleBot(BOT_TOKEN)

# Dictionaries for storing states
user_states = {}
user_irrigation_data = {}  # For storing irrigation data

# Water flow table (level in cm -> flow in m³/min)
WATER_FLOW_RATES = {
    0: 0,
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
    """
    When chat_id is None:
    - Return [<databases.backends.common.records.Record>]

    When chat_id is not None:
    - Return None if there was an error (and send an error message to the user)
    - Return <databases.backends.common.records.Record> on success
    """
    query = """
    SELECT
        s.siteID,
        h.humanID,
        h.phone,
        h.firstName,
        s.irrigation,
        i.date,
        i.irrigationNeed,
        i.irrigationApp,
        h.telegramID,
        JSON_UNQUOTE(JSON_EXTRACT(s.fieldproperties, '$.type')) AS type,
        JSON_UNQUOTE(JSON_EXTRACT(s.fieldproperties, '$.measurement_device')) AS device,
        JSON_UNQUOTE(JSON_EXTRACT(s.fieldproperties, '$.Crop')) AS crop,
        JSON_EXTRACT(s.fieldproperties, '$.area') AS area,
        JSON_EXTRACT(s.fieldproperties, '$.IE') AS ie,
        JSON_EXTRACT(s.fieldproperties, '$.WA') AS wa,
        i.PHIc as phic,
        i.PHIt as phit
    FROM SitesHumans.Sites s
        JOIN SitesHumans.Humans h ON JSON_UNQUOTE(JSON_EXTRACT(s.fieldproperties, '$.humanID')) = h.humanID
        JOIN WWCServices.Irrigation i ON i.siteID = s.siteID
    WHERE
        s.irrigation = 1
        AND i.date = DATE_SUB(CURDATE(), INTERVAL 1 DAY)
    """

    if chat_id:
        queries = query + ' AND h.telegramID = :chat_id LIMIT 1'
        try:
            row = await database.fetch_one(query=queries, values={'chat_id': chat_id})

            if row is None:
                # We check whether the user is in the system at all (without reference to irrigation)
                user_exists = await database.fetch_one(
                    "SELECT 1 FROM SitesHumans.Humans WHERE telegramID = :chat_id LIMIT 1",
                    values={'chat_id': chat_id}
                )

                if user_exists:
                    await send_message_safe(
                        chat_id,
                        _("❌ I have you registered, but I don't find the required irrigation data in the system. Please contact support or try again tomorrow.")
                    )
                    return None
                else:
                    # The user is not in the system at all
                    await send_message_safe(
                        chat_id,
                        _("❌ I am sorry, your telegramID is not in our system. Please contact support.")
                    )
                    return None

            irrigation_app = row['irrigationApp'] if 'irrigationApp' in row else 0
            irrigation_need = row['irrigationNeed']

            print(
                f"[DEBUG] irrigation_app: {irrigation_app}, irrigation_need: {irrigation_need}")

            # 1. Check: if irrigation is already applied
            if irrigation_app is not None and irrigation_app > 0:
                await send_message_safe(
                    chat_id,
                    _("❌ I am sorry, you have already registered your irrigation. Please contact support.")
                )
                return None

            return row
        except Exception as e:
            print(f"Database error for chat_id {chat_id}: {str(e)}")
            await send_message_safe(
                chat_id,
                _("⚠️ I cannot read from the database. Try again later or contact support.")
            )
            return None

    return await database.fetch_all(query=query)


BUTTONS = {
    "start_irrigation": _("Start Irrigation"),
    "irrigation_finished": _("Irrigation finished"),
}


def create_reply_keyboard():
    markup = types.ReplyKeyboardMarkup(row_width=2, resize_keyboard=True)
    buttons = [
        types.KeyboardButton(BUTTONS["start_irrigation"]),
        types.KeyboardButton(BUTTONS["irrigation_finished"]),
    ]
    markup.add(*buttons)
    return markup


def start_irrigation_notifications(chat_id):
    notification_manager.add_job(chat_id, 'water_check', send_water_check_notification,
                                 trigger=IntervalTrigger(minutes=20))


async def send_water_check_notification(chat_id):
    """Sends a notification about checking the water level"""
    if chat_id in user_irrigation_data:
        await send_message_safe(
            chat_id,
            _("🔄 Please check the current water level in the channel. If it has changed by more than 2cm, press 'Start irrigation' again and update the water level.")
        )


def schedule_polyv_completion_notification(chat_id, hours, minutes):
    completion_time = datetime.now() + timedelta(hours=hours, minutes=minutes)
    notification_manager.add_job(chat_id, 'polyv_complete', notify_polyv_completion,
                                 trigger=DateTrigger(run_date=completion_time))


async def notify_polyv_completion(chat_id):
    if chat_id in user_irrigation_data and user_irrigation_data[chat_id].get('is_active', False):
        message = _(
            "⏰ Watering time is over! Please stop the water flow and then click the 'Irrigation finished' button.")
        await send_message_safe(chat_id, message)
        notification_manager.remove_job(chat_id, 'water_check')


async def send_message_safe(chat_id, text, reply_markup=None):
    if text is None:
        return

    try:
        if reply_markup:
            await bot.send_message(chat_id, text, reply_markup=reply_markup)
        else:
            await bot.send_message(chat_id, text)
        print(f"[MESSAGE_SENT] To {chat_id}: {text}")
        return True
    except Exception as e:
        print(f"[MESSAGE_FAILED] To {chat_id}: {str(e)}")
        traceback.print_exc()
        return False


async def check_irrigation(chat_id):
    try:
        row = await get_irrigation_data(chat_id)
        print(f"[DEBUG] check_irrigation: row = {row}, type = {type(row)}")
        if row is None:
            return False

        if 'type' not in row or 'device' not in row:
            print(f"[ERROR] Invalid row data for chat_id: {chat_id}")
            await send_message_safe(
                chat_id,
                _("❌ Missing information: I have not found field type (control/treatment) or meter type in my database for your site. Please contact support.")
            )
            return False

        print(f"[DEBUG] Processing irrigation for: {row['firstName']} (type: {row['type']}, device: {row['device']})")

        crop = row['crop'] if 'crop' in row else 'crop'
        phic = row['phic']
        phit = row['phit']

        if 'irrigationNeed' not in row or 'area' not in row or 'wa' not in row or 'ie' not in row:
            print(f"[ERROR] Missing required fields in row data for chat_id: {chat_id}")
            await send_message_safe(
                chat_id,
                _("❌ Missing information: I have not found irrigationNeed, area, wetted area or irrigation efficiency in my database for your site. Please contact support.")
            )
            return False

        m3_needed = (float(row['irrigationNeed']) * 10 * float(row['area']) * float(row['wa'])) / float(row['ie'])

        if row['type'] == "treatment":
            if row['device'] in ["thomson_profile", "incremental_meter"] and phic <= phit:
                text = _(
                    "🌤 Good morning, {first_name}, on your treatment plot, growing {crop}.\n"
                    "I will give you a recommendation for irrigation and will guide you through the data entry.\n"
                    "💧 Your plot needs: {water:.2f} m³ of irrigation.\n"
                    "If you want to irrigate, press 'Start irrigation'. Otherwise simply come back tomorrow."
                )
            elif row['device'] == "total_meter" and phic <= phit:
                text = _(
                    "🌤 Good morning, {first_name}, on your treatment plot, growing {crop}.\n"
                    "I will give you a recommendation for irrigation and will guide you through the data entry.\n"
                    "💧 Please irrigate: {water:.2f} m³.\n"
                    "When finished, press the 'Irrigation finished' button."
                )
            else:
                text = _(
                    "🌤 Good morning, {first_name}, on your treatment plot, growing {crop}.\n"
                    "I will give you a recommendation for irrigation and will guide you through the data entry:\n"
                    "💧 Your plot is currently not under water stress, and I don't recommend to irrigate.\n"
                    "If you want to irrigate nevertheless, don't apply more than {water:.2f} m³ of irrigation.\n"
                    "Press 'Start irrigation' if you want to irrigate. Otherwise simply come back tomorrow."
                )


        elif row['type'] == "control":
            if row['device'] == "total_meter":
                text = _(
                    "🌤 Good morning, {first_name}, on your control plot, growing {crop}.\n"
                    "I will guide you through the irrigation data entry.\n"
                    "If you want to irrigation today, please go ahead.\n"
                    "When you have finished irrigation, press button 'Irrigation finished'. Otherwise simply come back tomorrow."
                )
            elif row['device'] in ["incremental_meter", "thomson_profile"]:
                text = _(
                    "🌤 Good morning, {first_name}, on your control plot, growing {crop}.\n"
                    "I will guide you through the irrigation data entry.\n"
                    "If you want to irrigate today, press 'Start irrigation'. Otherwise simply come back tomorrow."
                )
        else:
            await send_message_safe(chat_id,
                                    _("⚠️ The plot type or metering device information in the database is wrong for your site. Please contact support."))
            return False

        message = text.format(
            first_name=row['firstName'],
            water=round(m3_needed, 2),
            crop=crop  # Use crop variable instead of row.get()
        )
        markup = create_reply_keyboard()
        await send_message_safe(chat_id, message, reply_markup=markup)
        return True

    except Exception as e:
        print(f"[ERROR] in check_irrigation for {chat_id}: {str(e)}")
        traceback.print_exc()
        await send_message_safe(chat_id, _("⚠️ I cannot read from the database. Try again later or contact support."))
        return False


async def check_all_users():
    notified_users = set()
    try:
        rows = await get_irrigation_data()
        if not rows:
            print("[INFO] No users found for irrigation check")
            return

        for row in rows:
            if 'telegramID' not in row:
                continue

            chat_id = row['telegramID']
            if chat_id in notified_users:
                continue

            try:
                success = await check_irrigation(chat_id)
                if success:
                    notified_users.add(chat_id)
            except Exception as e:
                print(f"[ERROR] Notification error for {chat_id}: {str(e)}")
                traceback.print_exc()
    except Exception as e:
        print(f"[CRITICAL] Error in check_all_users: {str(e)}")
        traceback.print_exc()


async def calculate_irrigation(chat_id, water_level, irrigation_need, area, ie, wa):
    try:
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
        print(remaining_m3)
        flow_rate = WATER_FLOW_RATES.get(water_level, 0)
        print(flow_rate)
        remaining_time = round(remaining_m3 / flow_rate) if flow_rate > 0 else 24 * 60
        hours, minutes = remaining_time // 60, remaining_time % 60
        print(f'{remaining_time=} minutes')

        # Here we are planning a notification of completion
        if remaining_time >= 0:
            print(hours, minutes)
            schedule_polyv_completion_notification(chat_id, hours, minutes)

        return {
            'used_m3': user_irrigation_data[chat_id]['total_used_m3'],
            'remaining_m3': remaining_m3,
            'remaining_time': (hours, minutes),
            'is_completed': remaining_m3 <= 0,
        }
    except Exception as e:
        print(f"[ERROR] in calculate_irrigation for {chat_id}: {str(e)}")
        traceback.print_exc()
        raise


@bot.message_handler(commands=['start'])
async def start(message):
    try:
        chat_id = message.chat.id

        # Reset all user data and states
        if chat_id in user_irrigation_data:
            print(f"[DEBUG] Clearing irrigation data for {chat_id} due to /start command")
            del user_irrigation_data[chat_id]

        if chat_id in user_states:
            print(f"[DEBUG] Clearing user state for {chat_id} due to /start command")
            del user_states[chat_id]

        # Remove all notifications for this user
        notification_manager.remove_all_jobs(chat_id)

        # Delete the message about no need for irrigation (if it was sent)
        no_irrigation_key = f"no_irrigation_msg_{chat_id}"
        if no_irrigation_key in user_states:
            del user_states[no_irrigation_key]

        await send_message_safe(message.chat.id, _("The bot has started successfully"))
        await check_irrigation(message.chat.id)
    except Exception as e:
        print(f"[ERROR] in start command: {str(e)}")
        traceback.print_exc()


@bot.message_handler(func=lambda message: message.text == BUTTONS["start_irrigation"])
async def handle_recommendation(message):
    chat_id = message.chat.id
    try:

        row = await get_irrigation_data(chat_id)
        if row is None:
            print("[DEBUG] Row is False, returning")
            return

        if row['type'] == "treatment" and row['device'] == "thomson_profile":
            user_states[chat_id] = "waiting_for_water_level"
            await send_message_safe(
                chat_id,
                _("As soon as the water level has stabilized, enter the water level (in cm):")
            )
            return

        if row['device'] == "incremental_meter":
            await send_message_safe(chat_id, _("Enter the m³ on your counter BEFORE irrigation:"))
            user_states[chat_id] = "waiting_for_counter_start"
            return

        if row['type'] == "control" and row['device'] == "thomson_profile":
            await send_message_safe(chat_id,
                                    _("As soon as the water level has stabilized, enter the water level (in cm):"))
            user_states[chat_id] = "waiting_for_water_level_control"
            return

        if row['device'] == "total_meter":
            await send_message_safe(chat_id, _("After irrigation, press 'Irrigation finished' and enter m³ used water in total"))
            return

        else:
            await send_recommendation(
                chat_id,
                row['type'],
                float(row['irrigationNeed']),
                float(row['area']),
                float(row['ie']),
                float(row['wa'])
            )

    except Exception as e:
        print(f"[ERROR] in handle_recommendation: {str(e)}")
        traceback.print_exc()
        await send_message_safe(chat_id,
                                _("⚠️ I cannot read from the database. Try again later or contact support."))


@bot.message_handler(func=lambda message: user_states.get(message.chat.id) == 'waiting_for_water_level_control')
async def handle_water_level_control(message):
    chat_id = message.chat.id

    try:
        water_level = int(message.text)

        print(f"[DEBUG] Water level input: {water_level} for chat {chat_id}")
        print(f"[DEBUG] Current user_irrigation_data: {user_irrigation_data.get(chat_id)}")

        if water_level < 0 or water_level > 25:
            await send_message_safe(chat_id, _("⚠️ I need a water level from 0 to 25 cm.\n"
                                               "Please enter the correct value as a whole number (e.g. 0, 1, 2...):"))
            return

        current_time = datetime.now()

        if chat_id not in user_irrigation_data:
            # first level input
            user_irrigation_data[chat_id] = {
                'type': 'control',
                'device': 'thomson_profile',
                'levels': [(water_level, current_time)],
                'total_used': 0.0
            }
            await send_message_safe(
                chat_id,
                _("✅ Thank you. Whenever the water level changes by more than 2cm press 'Start irrigation' and enter the new level.\n"
                  "Enter 0 if water stops. Press 'Irrigation finished' when done.")
            )
        else:
            # subsequent level inputs
            last_level, last_time = user_irrigation_data[chat_id]['levels'][-1]
            flow_rate = WATER_FLOW_RATES.get(last_level, 0)
            time_diff = (current_time - last_time).total_seconds() / 60  # in minutes

            used_water = flow_rate * time_diff
            user_irrigation_data[chat_id]['total_used'] += used_water
            user_irrigation_data[chat_id]['levels'].append((water_level, current_time))

            await send_message_safe(
                chat_id,
                _("🔄 Updated: +{used_water:.2f} m³ used (total: {total_used:.2f} m³).\n"
                  "Whenever the water level changes by more than 2cm press 'Start irrigation' and enter the new level.\n"
                  "Enter 0 if water stops. Press 'Irrigation finished' when done.").format(
                    used_water=used_water,
                    total_used=user_irrigation_data[chat_id]['total_used']
                )
            )

        user_states[chat_id] = None  # resetting the state

    except ValueError:
        await send_message_safe(chat_id, _("⚠️ I need a water level from 0 to 25 cm.\n"
                                            "Please enter the correct value as a whole number (e.g. 0, 1, 2...):"))
    except Exception as e:
        print(f"[ERROR] in handle_water_level_control: {str(e)}")
        traceback.print_exc()
        await send_message_safe(chat_id, _("⚠️ An error occurred. Please try again. If you get this message again, contact support."))


@bot.message_handler(func=lambda message: user_states.get(message.chat.id) == 'waiting_for_counter_start')
async def handle_counter_start(message):
    chat_id = message.chat.id
    try:
        row = await get_irrigation_data(chat_id)
        if row is None:
            return

        # Store initial value for ANY field type
        start_counter = int(message.text)
        if start_counter < 0:
            await send_message_safe(
                chat_id,
                _("⚠️ The value cannot be negative. Please try again with a positive number.")
            )
            return
        user_irrigation_data[chat_id] = {
            'start_counter': start_counter,
            'type': row['type'],  # "control" or "treatment"
            'device': row['device']  # For possible checks
        }

        if row['type'] == "treatment" and row['device'] == "incremental_meter":
            # For treatment - show target_counter (old logic)
            m3_needed = (float(row['irrigationNeed']) * 10 * float(row['area']) * float(row['wa'])) / float(
                row['ie'])
            target_counter = start_counter + m3_needed
            await send_message_safe(
                chat_id,
                _("✅ Thank you. Irrigate until your counter is at: {target_counter:.2f} m³\n"
                  "💧 Water needed: {m3_needed:.2f} m³\n"
                  "When you have finished irrigation, press button ‘Irrigation finished.'").format(
                    target_counter=target_counter,
                    m3_needed=m3_needed
                )
            )
        else:
            # For control (or other devices) - just confirm
            await send_message_safe(
                chat_id,
                _("✅ When you have finished irrigation, press button 'Irrigation finished.'")
            )

        user_states[chat_id] = None  # Resetting the state

    except ValueError:
        await send_message_safe(chat_id, _("⚠️ Please enter a valid positive number (e.g., 125.5)."))
    except Exception as e:
        print(f"[ERROR] in handle_counter_start: {str(e)}")
        traceback.print_exc()
        await send_message_safe(chat_id, _("⚠️ An error occurred. Please try again. If you get this message again, contact support."))


@bot.message_handler(func=lambda message: user_states.get(message.chat.id) == 'waiting_for_water_level')
async def handle_water_level(message):
    chat_id = message.chat.id
    try:
        water_level = int(message.text)

        # We check that the water level is within the acceptable range.
        if water_level < 0 or water_level > 25:
            await send_message_safe(
                chat_id,
                _("⚠️ I need a water level from 0 to 25 cm.\n"
                  "Please enter the correct value as a whole number (e.g. 0, 1, 2...):")
            )
            return  # We do not continue processing.

        row = await get_irrigation_data(chat_id)
        if row is None:
            return

        calculation = await calculate_irrigation(
            chat_id,
            water_level,
            float(row['irrigationNeed']),
            float(row['area']),
            float(row['ie']),
            float(row['wa']),
        )

        if not calculation['is_completed']:
            hours, minutes = calculation['remaining_time']

            msg = _(
                "Thank you. 💦 At this level {water_level} cm, the recommended irrigation duration is ⏱ {hours}h {minutes}m\n"
                "Whenever the water level changes by more than 2cm, press 'Start irrigation' one more time and enter the new water level.\n"
                "Enter 0 if no water flows. Press 'Irrigation finished' when you stop.\n"
                "📊 Used: {used_m3:.2f} m³ of {total_m3:.2f} m³"
            ).format(
                water_level=water_level,
                hours=hours,
                minutes=minutes,
                used_m3=calculation['used_m3'],
                total_m3=calculation['used_m3'] + calculation['remaining_m3'],
            )

            await send_message_safe(chat_id, msg)

        user_states[chat_id] = None
    except ValueError:
        await send_message_safe(chat_id, _("⚠️ I need a water level from 0 to 25 cm.\n"
                                           "Please enter the correct value as a whole number (e.g. 0, 1, 2...):"))
    except Exception as e:
        print(f"[ERROR] in handle_water_level: {str(e)}")
        traceback.print_exc()
        await send_message_safe(chat_id, _("⚠️ I need a water level from 0 to 25 cm.\n"
                                           "Please enter the correct value as a whole number (e.g. 0, 1, 2...):"))


@bot.message_handler(func=lambda message: message.text == BUTTONS["irrigation_finished"])
async def handle_send_data(message):
    chat_id = message.chat.id
    try:
        # Stop all notifications
        notification_manager.remove_all_jobs(chat_id)

        row = await get_irrigation_data(chat_id)
        if row is None:
            print("[DEBUG] Row is None, returning")
            return

        irrigation_app = row['irrigationApp'] if 'irrigationApp' in row else 0
        print(f"[DEBUG] irrigation_app value: {irrigation_app}, type: {type(irrigation_app)}")
        try:
            irrigation_app_float = float(irrigation_app)
            if irrigation_app_float > 0:
                await send_message_safe(
                    chat_id,
                    _("❌ I am sorry, you have already registered your irrigation. Please contact support.")
                )
                print(f"[DEBUG] Irrigation already registered: {irrigation_app_float}, stopping bot")
                return  # Завершаем работу бота
        except (ValueError, TypeError):
            print(f"[DEBUG] Could not convert irrigation_app to float: {irrigation_app}")

        if row['device'] == "total_meter":
            print("[SAVE_DATA_TOTAL_METER] Requesting actual water usage")
            await send_message_safe(chat_id, _("Please enter the volume that you irrigated today (in m³):"))
            user_states[chat_id] = "waiting_for_actual_data"
            return


        if row['device'] == "incremental_meter":
            if chat_id in user_irrigation_data and 'start_counter' in user_irrigation_data[chat_id]:
                print("[SAVE_DATA_COUNTER] Requesting end counter value")
                await send_message_safe(chat_id, _("Enter the m³ on your counter AFTER irrigation:"))
                user_states[chat_id] = "waiting_for_counter_end"
                return
            else:
                await send_message_safe(chat_id, _("I don't have the m³ on your counter from before the irrigation. Press 'Start irrigation' button to enter this first."))
                return


        if row['type'] == "control" and row['device'] == "thomson_profile":
            if chat_id in user_irrigation_data and 'levels' in user_irrigation_data[chat_id]:
                data = user_irrigation_data[chat_id]

                # Calculating the last period of watering
                if data['levels']:  # If there is at least one dimension
                    last_level, last_time = data['levels'][-1]
                    flow_rate = WATER_FLOW_RATES.get(last_level, 0)
                    time_diff = (datetime.now() - last_time).total_seconds() / 60
                    data['total_used'] += flow_rate * time_diff

                    # Saving data
                    await save_irrigation_data(chat_id, data['total_used'], row)
                    del user_irrigation_data[chat_id]
            else:
                await send_message_safe(chat_id, _("❌ No active irrigation session found. Press 'Start irrigation' button to start one."))
            return

        elif row['type'] == "treatment" and row['device'] == "thomson_profile":
            # For treatment type and thomson device we immediately calculate and save the data
            if chat_id in user_irrigation_data and user_irrigation_data[chat_id].get('is_active', False):
                try:
                    data = user_irrigation_data[chat_id]
                    time_elapsed = (datetime.now() - data['last_update']).total_seconds()
                    flow_rate = WATER_FLOW_RATES.get(data['current_level'], 0)
                    additional_used = flow_rate * (time_elapsed / 60)
                    data['total_used_m3'] += additional_used

                    await save_irrigation_data(chat_id, data['total_used_m3'], row)

                    data['is_active'] = False
                    return
                except Exception as e:
                    print(f"Error while saving: {str(e)}")
                    await send_message_safe(chat_id, _("⚠️ Error saving data. Please contact support."))
            else:
                await send_message_safe(chat_id,
                                        _("❌ No active irrigation session found. Press 'Start irrigation' button to start one."))

        else:
            await send_message_safe(chat_id,
                                    _("⚠️ The plot type or metering device information in the database is wrong for your site. Please contact support."))
    except Exception as e:
        print(f"[ERROR] in handle_send_data: {str(e)}")
        traceback.print_exc()
        await send_message_safe(chat_id, _("⚠️ An error occurred. Please try again. If you get this message again, contact support."))


@bot.message_handler(func=lambda message: user_states.get(message.chat.id) == 'waiting_for_counter_end')
async def handle_counter_end(message):
    chat_id = message.chat.id
    try:
        end_counter = int(message.text)

        if chat_id not in user_irrigation_data or 'start_counter' not in user_irrigation_data[chat_id]:
            await send_message_safe(chat_id,
                                    _("I don't have the m³ on your counter from before the irrigation. Press 'Start irrigation' button to enter this first."))
            user_states[chat_id] = None
            return

        start_counter = user_irrigation_data[chat_id]['start_counter']
        if end_counter <= start_counter:
            await send_message_safe(chat_id, _("⚠️ The m³ on your counter after irrigation must be more than what it was before irrigation.\n"
                                                "Please enter the m³ on your counter after irrigation again!"))
            # We do NOT reset the state so that the user can enter the correct value.
            return

        used_m3 = end_counter - start_counter

        # OPTIMIZED: Get row once and pass to save_irrigation_data
        row = await get_irrigation_data(chat_id)
        if row is None:
            return

        await save_irrigation_data(chat_id, used_m3, row)

        # Only upon successful completion we reset the state
        user_states[chat_id] = None
        if chat_id in user_irrigation_data:
            del user_irrigation_data[chat_id]

    except ValueError:
        await send_message_safe(chat_id, _("⚠️ Please enter a valid positive number (e.g., 125.5)."))
        # We do NOT reset the state so that the user can repeat the input.
    except Exception as e:
        print(f"[ERROR] in handle_counter_end: {str(e)}")
        traceback.print_exc()
        await send_message_safe(chat_id, _("⚠️ An error occurred. Please try again. If you get this message again, contact support."))
        # We reset the state only in case of critical errors
        user_states[chat_id] = None
        if chat_id in user_irrigation_data:
            del user_irrigation_data[chat_id]


@bot.message_handler(func=lambda message: user_states.get(message.chat.id) == 'waiting_for_actual_data')
async def handle_actual_data(message):
    chat_id = message.chat.id
    try:
        actual_m3 = int(message.text)
        if actual_m3 < 0:
            await send_message_safe(chat_id, _("⚠️Error: The value cannot be negative. Please try again with a positive number."))
            return

        row = await get_irrigation_data(chat_id)
        if row is None:
            return

        await save_irrigation_data(chat_id, actual_m3, row)
        user_states[chat_id]=None
        
    except ValueError:
        await send_message_safe(chat_id, _("⚠️ Please enter a valid positive number (e.g., 125.5)."))
    except Exception as e:
        print(f"[ERROR] in handle_actual_data: {str(e)}")
        traceback.print_exc()
        await send_message_safe(chat_id, _("⚠️ An error occurred. Please try again. If you get this message again, contact support."))
    


async def send_recommendation(chat_id, fieldtype, device, irrigation_need, area, ie, wa, water_level=None):
    try:
        if fieldtype == 'treatment' and device == "thomson_profile" and water_level is not None:
            calculation = await calculate_irrigation(chat_id, water_level, irrigation_need, area, ie, wa)

            if calculation['is_completed']:
                msg = _("✅ Enough water, please stop irrigation.")
            else:
                hours, minutes = calculation['remaining_time']

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
        elif fieldtype == ['treatment'] and device == ['total_meter']:
            m3_need = (irrigation_need * 10 * area * wa) / ie
            m3_need = round(m3_need, 2)
            msg = _("🔢 Required: {m3_need} m³ water").format(m3_need=m3_need)
        else:
            msg = _("❌ I cannot provide you with a recommendation for your field type / metering device. Please contact support.")

        await send_message_safe(chat_id, msg)
    except (ValueError, TypeError):
        await send_message_safe(chat_id, _("⚠️ I could not calculate the recommended irrigation duration and volume. Please contact support."))
    except Exception as e:
        print(f"[ERROR] in send_recommendation: {str(e)}")
        traceback.print_exc()
        await send_message_safe(chat_id, _("⚠️ An error occurred. Please try again. If you get this message again, contact support."))


async def save_irrigation_data(chat_id, used_m3, row):
    """
    Output values:
    - False if there was an error
    - True on success
    """

    # This must never happen, it's only for development
    if row is None:
        raise ValueError('row must not be None')

    try:
        print(f"[SAVE_DATA_START] chat_id: {chat_id}, used_m3: {used_m3}")
        site_id = row['siteID']
        print(f"[SAVE_DATA_DEBUG] Using site_id: {site_id} for chat_id: {chat_id}")

        # Extract parameters from the row we already have
        area = float(row['area'])
        ie = float(row['ie'])
        wa = float(row['wa'])

        # Calculate actual mm
        actual_mm = (used_m3 * ie) / (10 * area * wa)
        print(f"[SAVE_DATA_CALC] used_m3: {used_m3} -> actual_mm: {actual_mm}")

        # Update irrigation data
        update_query = """
        UPDATE WWCServices.Irrigation
        SET irrigationApp = :actual_mm
        WHERE siteID = :site_id
        AND date = DATE_SUB(CURDATE(), INTERVAL 1 DAY)
        """
        print(f"[SAVE_DATA_UPDATE] Executing update with params: {actual_mm}, {site_id}")

        await database.execute(
            query=update_query,
            values={"actual_mm": actual_mm, "site_id": site_id}
        )

        success_msg = _(
            "✅ Data saved!\n"
            "Water used: {used_m3:.2f} m³\n"
            "Equivalent to: {actual_mm:.2f} mm\n"
            "See you tomorrow!"
        ).format(used_m3=used_m3, actual_mm=actual_mm)

        print(f"[SAVE_DATA_SUCCESS] {success_msg}")
        await send_message_safe(chat_id, success_msg)
        return True

    except Exception as e:
        print(f"[SAVE_DATA_EXCEPTION] Error saving data: {e}\nTraceback: {traceback.format_exc()}")
        error_msg = _("⚠️ Error saving data. Please contact support.")
        await send_message_safe(chat_id, error_msg)
        return False


async def main():
    try:
        print("[STARTUP] Connecting to database...")
        await database.connect()

        # Clearing old tasks on startup
        print("[STARTUP] Initializing scheduler...")
        scheduler.remove_all_jobs()

        # Check irrigation for all users, every day at 7 am
        scheduler.add_job(
            check_all_users,
            'cron',
            hour=7,
            minute=0,
            timezone=TIMEZONE
        )
        scheduler.start()
        print("[STARTUP] Scheduler started")

        # Start bot
        print("[STARTUP] Starting bot polling...")
        await bot.polling()

    except Exception as e:
        print(f"[FATAL ERROR] in main: {str(e)}")
        traceback.print_exc()
    finally:
        print("[SHUTDOWN] Shutting down...")
        try:
            scheduler.shutdown()
        except Exception:
            pass
        try:
            await database.disconnect()
        except Exception:
            pass
        print("[SHUTDOWN] Complete")


if __name__ == "__main__":
    asyncio.run(main())
