package models

import (
	"encoding/json"
	"errors"
	"log"
)

type HTTPError interface {
	error
	Status() int
	JSON() []byte
}

type baseError struct {
	Err     error
	status  int
	message string
	code    string
	details map[string]any
}

func (e *baseError) Error() string {
	return e.Err.Error()
}

func (e *baseError) Status() int {
	return e.status
}

func (e *baseError) JSON() []byte {
	message := e.message
	if message == "" {
		message = e.Err.Error()
	}
	resp := map[string]any{
		"error": message,
	}
	if e.code != "" {
		resp["code"] = e.code
	}
	if len(e.details) > 0 {
		resp["details"] = e.details
	}
	bytes, _ := json.Marshal(resp)
	return bytes
}

func Is(err, target error) bool {
	return errors.Is(err, target)
}

type ServerError struct {
	*baseError
}

type ValidationError struct {
	*baseError
}
type UnauthorizedError struct {
	*baseError
}
type ForbiddenError struct {
	*baseError
}

type NotFoundError struct {
	*baseError
}

func NewServerError(err error) *ServerError {
	log.Printf("[ERROR] %v", err)
	return &ServerError{
		&baseError{
			Err:     err,
			status:  500,
			code:    "ServerError",
			message: "Internal server error",
		},
	}
}

func NewValidationError(err error) *ValidationError {
	return &ValidationError{
		&baseError{
			Err:    err,
			status: 400,
			code:   "ValidationError",
		},
	}
}

func NewForbiddenError(msg string, err error) *ForbiddenError {
	return &ForbiddenError{
		&baseError{
			Err:     err,
			status:  403,
			message: msg,
			code:    "Forbidden",
		},
	}
}

func NewNotFoundError(msg string, err error) *NotFoundError {
	return &NotFoundError{
		&baseError{
			Err:     err,
			status:  404,
			message: msg,
			code:    "NotFound",
		},
	}
}

type ErrorResponse struct {
	Error string `json:"error" example:"An unexpected error occurred"`
	Code  string `json:"code" example:"InternalError"`
} // @name ErrorResponse
