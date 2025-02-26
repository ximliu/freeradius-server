#
#  Unit tests for unlang keywords
#


#
#  Test name
#
TEST := test.keywords

#
#  The test files are files without extensions.
#  The list is unordered.  The order is added in the next step by looking
#  at precursors.
#
FILES := $(filter-out %.ignore %.conf %.md %.attrs %.mk %~ %.rej,$(subst $(DIR)/,,$(wildcard $(DIR)/*)))

#
#  Don't run SSHA tests if there's no SSL
#
ifeq "$(OPENSSL_LIBS)" ""
FILES := $(filter-out pap-ssha2 sha2,$(FILES))
endif

#
#  Some tests require PCRE or PCRE2
#
ifeq "$(AC_HAVE_REGEX_PCRE)$(AC_HAVE_REGEX_PCRE2)" ""
FILES := $(filter-out if-regex-match-named,$(FILES))
endif

$(eval $(call TEST_BOOTSTRAP))

#
#  For each file, look for precursor test.
#  Ensure that each test depends on its precursors.
#
-include $(OUTPUT)/depends.mk

export OPENSSL_LIBS

$(OUTPUT)/depends.mk: $(addprefix $(DIR)/,$(FILES)) | $(OUTPUT)
	${Q}rm -f $@
	${Q}touch $@
	${Q}for x in $^; do \
		y=`grep 'PRE: ' $$x | sed 's/.*://;s/  / /g;s, , $(BUILD_DIR)/tests/keywords/,g'`; \
		if [ "$$y" != "" ]; then \
			z=`echo $$x | sed 's,src/,$(BUILD_DIR)/',`; \
			echo "$$z: $$y" >> $@; \
			echo "" >> $@; \
		fi \
	done

#
#  Cache the list of modules which are enabled, so that we don't run
#  the shell script on every build.
#
#  KEYWORD_MODULES := $(shell grep -- mods-enabled src/tests/keywords/unit_test_module.conf | sed 's,.*/,,')
#
$(OUTPUT)/enabled.mk: src/tests/keywords/unit_test_module.conf | $(OUTPUT)
	${Q}echo "KEYWORD_MODULES := " $$(grep -- mods-enabled src/tests/keywords/unit_test_module.conf | sed 's,.*/,,' | tr '\n' ' ' ) > $@
-include $(OUTPUT)/enabled.mk

KEYWORD_RADDB	:= $(addprefix raddb/mods-enabled/,$(KEYWORD_MODULES))
KEYWORD_LIBS	:= $(addsuffix .la,$(addprefix rlm_,$(KEYWORD_MODULES))) rlm_cache.la rlm_csv.la

#
#  Files in the output dir depend on the unit tests
#
#	src/tests/keywords/FOO		unlang for the test
#	src/tests/keywords/FOO.attrs	input RADIUS and output filter
#	build/tests/keywords/FOO	updated if the test succeeds
#	build/tests/keywords/FOO.log	debug output for the test
#
#  Auto-depend on modules via $(shell grep INCLUDE $(DIR)/radiusd.conf | grep mods-enabled | sed 's/.*}/raddb/'))
#
#  If the test fails, then look for ERROR in the input.  No error
#  means it's unexpected, so we die.
#
#  Otherwise, check the log file for a parse error which matches the
#  ERROR line in the input.
#
$(OUTPUT)/%: $(DIR)/% $(TEST_BIN_DIR)/unit_test_module | $(KEYWORD_RADDB) $(KEYWORD_LIBS) build.raddb rlm_cache_rbtree.la rlm_test.la rlm_csv.la rlm_unpack.la
	@echo "KEYWORD-TEST $(notdir $@)"
	${Q}cp $(if $(wildcard $<.attrs),$<.attrs,$(dir $<)/default-input.attrs) $@.attrs
	${Q}if ! KEYWORD=$(notdir $@) $(TEST_BIN)/unit_test_module -D share/dictionary -d src/tests/keywords/ -i "$@.attrs" -f "$@.attrs" -r "$@" -xx > "$@.log" 2>&1 || ! test -f "$@"; then \
		if ! grep ERROR $< 2>&1 > /dev/null; then \
			cat $@.log; \
			echo "# $@.log"; \
			echo "KEYWORD=$(notdir $@) $(TEST_BIN)/unit_test_module -D share/dictionary -d src/tests/keywords/ -i \"$@.attrs\" -f \"$@.attrs\" -r \"$@\" -xx"; \
			rm -f $(BUILD_DIR)/tests/test.keywords; \
			exit 1; \
		fi; \
		FOUND=$$(grep -E '^(Error : )?$<' $@.log | head -1 | sed 's/.*\[//;s/\].*//'); \
		EXPECTED=$$(grep -n ERROR $< | sed 's/:.*//'); \
		if [ "$$EXPECTED" != "$$FOUND" ]; then \
			cat $@.log; \
			echo "# $@.log"; \
			echo "KEYWORD=$(notdir $@) $(TEST_BIN)/unit_test_module -D share/dictionary -d src/tests/keywords/ -i \"$@.attrs\" -f \"$@.attrs\" -r \"$@\" -xx"; \
			rm -f $(BUILD_DIR)/tests/test.keywords; \
			exit 1; \
		else \
			touch "$@"; \
		fi \
	fi

$(TEST):
	@touch $(BUILD_DIR)/tests/$@
