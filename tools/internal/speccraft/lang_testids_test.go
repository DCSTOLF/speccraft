package speccraft

import "testing"

func eqStrings(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

func Test_GoTestIDs_ExtractsFuncTestNames(t *testing.T) {
	src := `package foo

import "testing"

// func TestOld(t *testing.T) {} // commented-out, must be ignored

func helper() {}

func TestFoo(t *testing.T) {}

func TestBar(t *testing.T) {
	_ = "TestNotAName"
}
`
	got := GoTestIDs(src)
	want := []string{"TestFoo", "TestBar"}
	if !eqStrings(got, want) {
		t.Errorf("GoTestIDs = %v, want %v", got, want)
	}
}

func Test_GoTestIDs_IgnoresBlockComment(t *testing.T) {
	src := `package foo
/*
func TestBlockCommented(t *testing.T) {}
*/
func TestReal(t *testing.T) {}
`
	got := GoTestIDs(src)
	want := []string{"TestReal"}
	if !eqStrings(got, want) {
		t.Errorf("GoTestIDs = %v, want %v", got, want)
	}
}

func Test_PythonTestIDs_ExtractsDefTestNames(t *testing.T) {
	src := `import pytest

# def test_old(self): pass   <- commented, ignored

def helper():
    pass

def test_bar(self):
    assert True

def test_baz():
    assert 1 == 1
`
	got := PythonTestIDs(src)
	want := []string{"test_bar", "test_baz"}
	if !eqStrings(got, want) {
		t.Errorf("PythonTestIDs = %v, want %v", got, want)
	}
}

func Test_JSTSTestIDs_ExtractsTestItDescribe(t *testing.T) {
	src := `import { test, it, describe } from 'vitest'

// it('old', () => {})  <- commented, ignored

test('x', () => {})
it("y", () => {})
describe('z', () => {
  it('nested', () => {})
})
`
	got := JSTSTestIDs(src)
	want := []string{"x", "y", "z", "nested"}
	if !eqStrings(got, want) {
		t.Errorf("JSTSTestIDs = %v, want %v", got, want)
	}
}

func Test_JSTSTestIDs_IgnoresBlockComment(t *testing.T) {
	src := `/* test('blockcommented', () => {}) */
test('real', () => {})
`
	got := JSTSTestIDs(src)
	want := []string{"real"}
	if !eqStrings(got, want) {
		t.Errorf("JSTSTestIDs = %v, want %v", got, want)
	}
}
