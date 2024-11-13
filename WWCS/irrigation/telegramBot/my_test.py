import telebot
import time

API_TOKEN = 'XXX'
# API_TOKEN = 'XXX'
bot = telebot.TeleBot(API_TOKEN)

@bot.message_handler(func=lambda message: True)
def catch_all(message):
    print('ECHO', message.chat.id, message.text)


# Замените на ваш реальный chat_id
# chat_id = 4160131435 # nemat, does not work
# chat_id = 5257578161 # jdavid
# chat_id = -4160131435 # works
# chat_id = 470103827  # nemat, works
chat_id = -4211160944

# Получение информации о чате
chat = bot.get_chat(chat_id)
print(f"Chat info: {chat}")

# Отправка сообщения в чат
message = "Привет, это тестовое сообщение!"
bot.send_message(chat_id, message)
print("Сообщение отправлено успешно!")


bot.infinity_polling()
