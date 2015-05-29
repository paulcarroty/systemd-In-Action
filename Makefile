%.html: %.md
	pandoc -f markdown -t html5 --standalone --smart $< -o $@
