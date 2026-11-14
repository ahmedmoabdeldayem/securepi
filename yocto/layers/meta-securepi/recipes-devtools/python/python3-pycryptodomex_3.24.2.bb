SUMMARY = "Cryptographic library for Python"
HOMEPAGE = "https://www.pycryptodome.org"
LICENSE = "BSD-2-Clause & Unlicense"
LIC_FILES_CHKSUM = "file://LICENSE.rst;md5=29242a70410a4eeff488a28164e7ab93"

inherit pypi setuptools3

PYPI_PACKAGE = "pycryptodomex"
SRC_URI[sha256sum] = "e4dbc29e2575365d15e272f769329106277649aea081e2119cf43d66950f8f8f"

BBCLASSEXTEND = "native"
