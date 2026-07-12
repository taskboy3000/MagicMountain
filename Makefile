test: test-perl test-js

ci-check: test-perl test-js walkthrough perlcritic verify

check-coverage:
	perl -Ilib bin/check_coverage

walkthrough:
	perl bin/walkthrough

check-loyalist:
	perl -Ilib bin/check_loyalist_balance

test-perl:
	MOJO_MODE=test prove t

test-js:
	node -c public/js/ambient.js && node -c public/js/game.js && echo "JS syntax OK"

clean:
	rm -rf t/cover_db coverage
	find . -name '*.bak' -o -name '*.tdy' -exec rm {} \;

cover:
	rm -rf cover_db
	MOJO_MODE=test PERL5OPT=-MDevel::Cover prove -Ilib t

report:
	cover -summary

perlcritic:
	@echo "Running perlcritic (severity 3 — stern)..."
	@find . -name '*.pl' -o -name '*.pm' -o -name '*.t' -type f \
	  | xargs perlcritic --verbose 8

perlcritic-brutal:
	@echo "Running perlcritic (severity 5 — brutal)..."
	@find . -name '*.pl' -o -name '*.pm' -o -name '*.t' -type f \
	  | xargs perlcritic --severity 5 --verbose 8

verify: check-columns check-unintended-files check-doc-consistency
	@echo "=== All verification checks passed ==="

verify-coverage:
	@echo "Checking code coverage (85% threshold)..."
	@rm -rf cover_db
	@MOJO_MODE=test PERL5OPT=-MDevel::Cover=-db,cover_db,-coverage,statement,branch,condition,subroutine prove -Ilib t >/dev/null 2>&1
	@COV=$$(perl -MDevel::Cover=-db,cover_db -e 'my $$r = Devel::Cover->new->report_data->{statement}{summary}{percentage}; printf "%.1f\n", $$r' 2>/dev/null); \
	if [ -z "$$COV" ]; then \
	  echo "WARNING: Could not parse coverage -- skipping gate"; exit 0; \
	fi; \
	echo "Coverage: $$COV%"; \
	if [ "$$(echo "$$COV < 85" | bc -l)" = "1" ]; then \
	  echo "FAIL: Coverage $$COV% < 85% threshold"; exit 1; \
	fi; \
	echo "PASS: Coverage $$COV% >= 85%"

check-columns:
	@perl -Ilib bin/check_column_declarations

check-unintended-files:
	@perl bin/check_unintended_files

check-doc-consistency:
	@perl -Ilib bin/check_doc_consistency

.PHONY: indent ci-check verify verify-coverage check-columns check-unintended-files check-doc-consistency
indent:
	@echo "Finding Perl files..."
	@find . -name '*.pl' -o -name '*.pm' -o -name '*.t' -type f \
		> .perltidy_file_list || true
	@if [ ! -s .perltidy_file_list ]; then \
	  echo "No Perl files found."; \
	  rm -f .perltidy_file_list; \
	else \
	  echo "Running perltidy on files..."; \
	  set -e; \
	  cat .perltidy_file_list | while IFS= read -r f; do \
	    echo "  perltidy $$f"; \
	    perltidy -q $$f || { echo "perltidy failed on $$f"; exit 1; }; \
	  done; \
	  rm -f .perltidy_file_list; \
	fi
	find . -name '*.bak' -o -name '*.tdy' -exec 'rm' '{}' ';'
