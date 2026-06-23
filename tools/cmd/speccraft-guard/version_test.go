package main

import "testing"

func Test_GuardCmd_Version_Const160(t *testing.T) {
	if version != "1.6.0" {
		t.Errorf("version = %q, want %q", version, "1.6.0")
	}
}
