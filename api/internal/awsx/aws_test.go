package awsx

import (
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestBuildTags_Empty(t *testing.T) {
	result := buildTags(map[string]string{})
	assert.Equal(t, "<Tagging><TagSet></TagSet></Tagging>", result)
}

func TestBuildTags_SingleTag(t *testing.T) {
	result := buildTags(map[string]string{
		"userId": "abc123",
	})
	assert.Equal(t, "<Tagging><TagSet><Tag><Key>userId</Key><Value>abc123</Value></Tag></TagSet></Tagging>", result)
}

func TestBuildTags_MultipleTags(t *testing.T) {
	result := buildTags(map[string]string{
		"userId":    "abc123",
		"workoutId": "2025-12-08T00:01:24.621971Z",
	})

	// Map iteration order is not guaranteed, so check for both tags
	assert.True(t, strings.HasPrefix(result, "<Tagging><TagSet>"))
	assert.True(t, strings.HasSuffix(result, "</TagSet></Tagging>"))
	assert.Contains(t, result, "<Tag><Key>userId</Key><Value>abc123</Value></Tag>")
	assert.Contains(t, result, "<Tag><Key>workoutId</Key><Value>2025-12-08T00:01:24.621971Z</Value></Tag>")
}

func TestBuildTags_EscapesHtml(t *testing.T) {
	result := buildTags(map[string]string{
		"key<>":  "value&\"'",
		"normal": "safe",
	})

	assert.Contains(t, result, "<Key>key&lt;&gt;</Key>")
	assert.Contains(t, result, "<Value>value&amp;&#34;&#39;</Value>")
	assert.Contains(t, result, "<Tag><Key>normal</Key><Value>safe</Value></Tag>")
}

func TestBuildTags_SpecialCharactersInValues(t *testing.T) {
	result := buildTags(map[string]string{
		"destination": "bucket-name",
		"path":        "workouts/user-123/file.png",
	})

	assert.Contains(t, result, "<Tag><Key>destination</Key><Value>bucket-name</Value></Tag>")
	assert.Contains(t, result, "<Tag><Key>path</Key><Value>workouts/user-123/file.png</Value></Tag>")
}

func TestBuildTags_UnicodeValues(t *testing.T) {
	result := buildTags(map[string]string{
		"name": "健身",
	})

	assert.Contains(t, result, "<Tag><Key>name</Key><Value>健身</Value></Tag>")
}
