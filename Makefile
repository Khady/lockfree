all:
	ocaml pkg/pkg.ml build --pinned false

clean:
	rm -rf clean
