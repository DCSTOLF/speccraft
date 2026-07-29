package main

import "testing"

func Test_DriftCmd_Version_Const1130(t *testing.T) {
	if version != "1.13.0" {
		t.Errorf("version = %q, want %q", version, "1.13.0")
	}
}
