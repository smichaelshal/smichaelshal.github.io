# Variables
DESTINATION = content/posts
INPUT_DIR = /Users/michael/Documents/Linux\ Kernel\ Docs\ v2
META_FILE = build/out_images.json
SCRIPT = build/fix_md_to_post.py
PYTHON_CMD = python3
HUGO_OUTPUT = public

# Targets
.PHONY: all clean clean_hugo clean_posts clean_all

# Default target
all:
	$(PYTHON_CMD) "$(SCRIPT)" -d "$(DESTINATION)" -i "$(INPUT_DIR)" -m "$(META_FILE)"

# Clean targets
clean: clean_hugo

clean_hugo:
	rm -rf $(HUGO_OUTPUT)

clean_posts:
	rm -rf $(DESTINATION)/*

clean_all: clean_hugo clean_posts
