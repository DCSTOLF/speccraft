package main

import "testing"

func Test_GuardCmd_Version_Const1170(t *testing.T) {
	if version != "1.17.0" {
		t.Errorf("version = %q, want %q", version, "1.17.0")
	}
}
