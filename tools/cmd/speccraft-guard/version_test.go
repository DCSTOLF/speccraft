package main

import "testing"

func Test_GuardCmd_Version_Const1120(t *testing.T) {
	if version != "1.12.0" {
		t.Errorf("version = %q, want %q", version, "1.12.0")
	}
}
