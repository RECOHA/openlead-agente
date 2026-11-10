# Builds the OpenLead skin CSS from LESS. Run from the Roundcube root with
# `make css-openlead` (installs the NPM dependencies first), or here with `make css`.
#
# --rewrite-urls=all keeps the url()s of the imported Elastic files pointing at
# skins/elastic (icons, Roboto fallback), while ours point at skins/openlead.
#
# Both styles.css and styles.min.css are needed: Elastic's layout.html asks for
# /styles/styles.css and Roundcube resolves it from the parent skin first, so the
# child skin must have the non-minified name too. Roundcube then serves the .min.css.

LESSC = npx lessc --rewrite-urls=all

css:
	for f in styles print embed; do \
		$(LESSC) styles/$$f.less > styles/$$f.css && \
		$(LESSC) --clean-css="--s1 --advanced" styles/$$f.less > styles/$$f.min.css || exit 1; \
	done
