APP := build/Claude Lights.app

.PHONY: app install run icon clean

app:
	./scripts/build-app.sh

install: app
	rm -rf "/Applications/Claude Lights.app"
	cp -R "$(APP)" /Applications/
	open "/Applications/Claude Lights.app"

run: app
	open "$(APP)"

icon:
	./scripts/make-icon.sh

clean:
	rm -rf .build build
