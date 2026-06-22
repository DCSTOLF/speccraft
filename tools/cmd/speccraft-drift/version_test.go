package main

import "testing"

func Test_DriftCmd_Version_Const150(t *testing.T) {
	if version != "1.5.0" {
		t.Errorf("version = %q, want %q", version, "1.5.0")
	}
}
