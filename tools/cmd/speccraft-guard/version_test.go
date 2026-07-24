package main

import "testing"

func Test_GuardCmd_Version_Const171(t *testing.T) {
	if version != "1.7.1" {
		t.Errorf("version = %q, want %q", version, "1.7.1")
	}
}
