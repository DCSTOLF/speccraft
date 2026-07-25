package main

import "testing"

func Test_GuardCmd_Version_Const190(t *testing.T) {
	if version != "1.9.0" {
		t.Errorf("version = %q, want %q", version, "1.9.0")
	}
}
