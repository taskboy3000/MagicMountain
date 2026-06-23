test: test-perl test-js test-boundaries

check-coverage:
	perl -Ilib bin/check_coverage

check-loyalist:
	perl -Ilib bin/check_loyalist_balance

test-perl:
	prove t

test-js:
	npm test

clean:
	rm -rf t/cover_db coverage

cover:
	rm -rf t/cover_db
	cd t && PERL5OPT=-MDevel::Cover prove -I../lib .

report:
	cd t && cover -summary

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
