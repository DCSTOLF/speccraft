package main

import "testing"

func Test_GuardCmd_Version_Const110(t *testing.T) {
	if version != "1.1.0" {
		t.Errorf("version = %q, want %q", version, "1.1.0")
	}
}
