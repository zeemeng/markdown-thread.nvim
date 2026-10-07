.PHONY: test

# Fixtures come from the markdown-thread spec repo (override with
# MDTHREAD_FIXTURES=/path/to/markdown-thread/fixtures).
test:
	nvim --headless -u NONE -l tests/run.lua
