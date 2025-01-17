# Translations

After a development, if the message strings have changed, the translation files must be
updated.

To add a new language first initialize. For example for Tajik:

    mkdir locale/tg/LC_MESSAGES -p
    msginit -l tg -o locale/tg/LC_MESSAGES/messages.po -i locale/messages.pot --no-translator

This is how the locale.pot file was generated for the first time:

    xgettext bot.py -o locale/messages.pot
    # Changed charset=CHARSET to charset=UTF-8
