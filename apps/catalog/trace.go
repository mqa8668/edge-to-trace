package main

import "strings"

// parseTraceparent extracts the trace id and parent span id from a W3C traceparent header.
// It returns ok=false for anything that is not a valid version-00 style header.
func parseTraceparent(h string) (traceID, parentID string, ok bool) {
	parts := strings.Split(strings.TrimSpace(h), "-")
	if len(parts) < 4 || len(parts[0]) != 2 || len(parts[1]) != 32 || len(parts[2]) != 16 || len(parts[3]) != 2 {
		return "", "", false
	}
	if parts[0] == "ff" || !isHex(parts[0]) || !isHex(parts[1]) || !isHex(parts[2]) || !isHex(parts[3]) {
		return "", "", false
	}
	if allZero(parts[1]) || allZero(parts[2]) {
		return "", "", false
	}
	return parts[1], parts[2], true
}

func isHex(s string) bool {
	for _, r := range s {
		if (r < '0' || r > '9') && (r < 'a' || r > 'f') {
			return false
		}
	}
	return true
}

func allZero(s string) bool { return strings.Trim(s, "0") == "" }
