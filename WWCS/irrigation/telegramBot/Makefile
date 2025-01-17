.PHONY: install test

install:
	python3 -m venv venv
	./venv/bin/pip install -U pip
	./venv/bin/pip install -r requirements.txt

gettext-template:
	xgettext bot.py -o locale/messages.pot

gettext-build:
	msgfmt -o locale/tg/LC_MESSAGES/messages.mo locale/tg/LC_MESSAGES/messages.po

test:
	./venv/bin/pytest test_bot.py
