PYTHON=python3
PIP=pip3

FILES=enable_guardduty.py

package: test clean zipfile

test: $(FILES)
	for f in $^; do $(PYTHON) -m py_compile $$f; if [ $$? -ne 0 ] ; then echo "$$f FAILS" ; exit 1; fi done

clean:
	rm -rf __pycache__ *.zip *.dist-info $(DEPENDENCIES)

# Create the package Zip. Assumes all tests were done
zipfile: $(FILES)
	zip -r $(LAMBDA_PACKAGE) $^
