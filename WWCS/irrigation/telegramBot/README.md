# Environment variables

A deployment of the irrigation bot is configured with a number of environemnet variables:

    USERNAME    -- Username to connect to MySQL (defaults to "wwcs")
    PASSWORD    -- Password to connect to MySQL (required)
    BOT_TOKEN   -- Token to connect to Telegram (required)
    LANGUAGE    -- Language to use (defaults to "en")

The environment variables should be defined in a file with the name ".env", located in the
directory where the bot runs. For example:

    ./WWCS/irrigation/telegramBot/.env

    USERNAME=wwcs
    PASSWORD=XXX
    BOT_TOKEN=XXXXXXXXXX:XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
    LANGUAGE=tg

Since this file contains sensitive information, set restrictive permissions, only the user
should be able to read/write it:

    chmod 600 ./WWCS/irrigation/telegramBot/.env

To register your bot and receive its authentication token start a converation with
@BotFather, then create a new bot, choose a bot name, and a username:

    /newbot
    [...]
    wwwc_test
    [...]
    wwcs_test_bot

@BotFather will reply with the token. To delete the bot send `/deletebot` to @BotFather.

# Translations

We only support one language per installation, and this should be defined by a
environement variable. When deployed, set the language in the .env file like this:

    LANGUAGE=tg

The source language is English (en), and there are translations available for Tajik (tg).

## Introduction

In the source files strings are marked for translation using gettext. For
example:

    _("Hello world")

In execution the gettext function will lookup the correct translation. This is also used
by the gettext command line programs to extract the strings to be translated, and generate
the PO files.

PO files are text files with the source messages (msgid) and their translations (msgstr).
For a new language the translations will be empty at the beginning.

The PO files must be edited to add or update the translations. And then the PO files must
be compiled to the MO binary format, which will be used when running the program.

## Required software

We use the following software for development (none of this is required in deployment):

- gettext: used to update the translation (PO) files and to compile them to MO files
- make: we use make to simplify the management of the files
- poedit: is a graphical application to edit the PO files, for translators

Install with:

    # Debian
    apt install gettext make poedit

## Update translations

After a development, if the message strings have changed, the translation files must be
updated:

    make update_po

Then the PO files must be edited to update the translations. We recommend to use poedit,
for example:

    poedit locale/tg/LC_MESSAGES/messages.po

When saving the PO file with poedit it should as well update the MO file, so no further
steps should be required. But if needed MO files can be explicitly updated with:

    make update_mo

All locale files should be commited, so don't forget to:

    git add locale

# Add a new language

To add a new language you need first to initialize the PO file. This is the procedure, for
example for the Khmer (km) language:

    mkdir locale/km/LC_MESSAGES -p
    msginit -l km -o locale/km/LC_MESSAGES/messages.po -i locale/messages.pot --no-translator

Now edit the Makefile and add the km language to the list of locales, for example:

    LOCALES = km tg

Then you can continue editing the PO file with poedit as described above.
