TESTS_INIT = tests/minimal_init.lua
TESTS_DIR = tests
STYLUA_FILES = lua $(TESTS_INIT) $(TESTS_DIR)/auto-venv/

# TODO: Add documentation generation with mini.doc

.PHONY: test
test:
	@nvim \
		--headless \
		--noplugin \
		-u $(TESTS_INIT) \
		-c "PlenaryBustedDirectory $(TESTS_DIR)/auto-venv { minimal_init = '$(TESTS_INIT)', sequential = true }"

.PHONY: lint
lint:
	@echo "Running lint checks..."
	@stylua --color always --check $(STYLUA_FILES)

.PHONY: format
format:
	@echo "Formatting code..."
	@stylua --color always $(STYLUA_FILES)

.PHONY: clean
clean:
	rm -rf $(TESTS_DIR)/test_projects
