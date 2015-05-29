SOURCES = $(wildcard part*.md)
NAME = $(shell basename "$$(pwd)")

.PHONY: all clean

all: $(NAME).html

clean:
	rm -f $(NAME).md *.html

$(NAME).md: $(SOURCES)
	cat $^ > $@

%.html: %.md
	pandoc -f markdown -t html5 --standalone --smart $(PANDOC_FLAGS) $< -o $@
