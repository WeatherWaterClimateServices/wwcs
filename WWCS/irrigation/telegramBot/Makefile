.PHONY: install update_po update_mo

LOCALES = tg
PO_FILES = $(foreach loc,$(LOCALES),locale/$(loc)/LC_MESSAGES/messages.po)

install:
	python3 -m venv venv
	./venv/bin/pip install -U pip
	./venv/bin/pip install -r requirements.txt

update_po:
	xgettext bot.py -o locale/messages.pot
	$(foreach po,$(PO_FILES),msgmerge --update $(po) locale/messages.pot;)

update_mo:
	$(foreach loc,$(LOCALES),msgfmt -o locale/$(loc)/LC_MESSAGES/messages.mo locale/$(loc)/LC_MESSAGES/messages.po)
