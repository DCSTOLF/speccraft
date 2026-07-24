package main

import "testing"

func Test_DriftCmd_Version_Const170(t *testing.T) {
	if version != "1.7.0" {
		t.Errorf("version = %q, want %q", version, "1.7.0")
	}
}
