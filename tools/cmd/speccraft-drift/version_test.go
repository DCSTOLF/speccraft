package main

import "testing"

func Test_DriftCmd_Version_Const180(t *testing.T) {
	if version != "1.8.0" {
		t.Errorf("version = %q, want %q", version, "1.8.0")
	}
}
