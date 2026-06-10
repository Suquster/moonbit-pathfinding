// Root package for executable documentation.
//
// MoonBit treats any directory with a `moon.pkg` file as a package; it also
// requires at least one `.mbt` source file in order to run the package's
// `README.mbt.md` as a black-box documentation test.  This file is that
// documentation anchor: it intentionally defines no public API, keeping the
// root package focused on README doctests while implementation packages live
// under `src/`.
