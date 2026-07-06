test: test-perl test-js

ci-check: test-perl test-js walkthrough perlcritic

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

.PHONY: indent
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
