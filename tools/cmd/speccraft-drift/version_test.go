package main

import "testing"

func Test_DriftCmd_Version_Const161(t *testing.T) {
	if version != "1.6.1" {
		t.Errorf("version = %q, want %q", version, "1.6.1")
	}
}
