# Copyright (C) 2023 Toitware ApS.

.PHONY: all
all: test

.PHONY: install-pkgs
install-pkgs: rebuild-cmake
	(cd build && ninja download_packages)

.PHONY: test
test: install-pkgs rebuild-cmake
	(cd build && ninja check)

.PHONY: start-supabase stop-supabase

start-supabase:
	@ if supabase status --workdir tests/supabase_test &> /dev/null; then \
	  supabase db reset --workdir tests/supabase_test; \
	else \
	  supabase start --workdir tests/supabase_test; \
	fi

stop-supabase:
	@ supabase stop --workdir tests/supabase_test

# We rebuild the cmake file all the time.
# We use "glob" in the cmakefile, and wouldn't otherwise notice if a new
# file (for example a test) was added or removed.
# It takes <1s on Linux to run cmake, so it doesn't hurt to run it frequently.
.PHONY: rebuild-cmake
rebuild-cmake:
	mkdir -p build
	(cd build && cmake .. -G Ninja)
