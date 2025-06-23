TESTS_INIT = tests/minimal_init.lua
TESTS_DIR = tests

# TODO: Add documentation generation with mini.doc

.PHONY: test
test:
	@nvim \
		--headless \
		--noplugin \
		-u $(TESTS_INIT) \
		-c "PlenaryBustedDirectory $(TESTS_DIR)/auto-venv { minimal_init = '$(TESTS_INIT)', sequential = true }"


.PHONY: clean
clean:
	rm -rf $(TESTS_DIR)/test_projects
