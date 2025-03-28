package errors

import (
	"errors"

	client "github.com/Yamashou/gqlgenc/clientv2"
)

type KnownError string

func (k KnownError) String() string {
	return string(k)
}

func (k KnownError) Error() string {
	return string(k)
}

const (
	ErrorNotFound             KnownError = "could not find resource"
	ErrorNotFoundOIDCProvider KnownError = "the resource you requested was not found"
	ErrRetriable              KnownError = "still waiting on read/write bindings, requeueing until they're available"
	ErrDeleteRepository                  = "could not delete repository"
)

type wrappedErrorResponse struct {
	err *client.ErrorResponse
}

func (er *wrappedErrorResponse) Has(err KnownError) bool {
	if er.err.GqlErrors == nil {
		return false
	}

	for _, g := range *er.err.GqlErrors {
		if g.Message == string(err) {
			return true
		}
	}

	return false
}

func newAPIError(err *client.ErrorResponse) *wrappedErrorResponse {
	return &wrappedErrorResponse{
		err: err,
	}
}

func IsNotFound(err error) bool {
	if err == nil {
		return false
	}

	errorResponse := new(client.ErrorResponse)
	ok := errors.As(err, &errorResponse)
	if !ok {
		return false
	}

	return newAPIError(errorResponse).Has(ErrorNotFound) || newAPIError(errorResponse).Has(ErrorNotFoundOIDCProvider)
}

func IgnoreNotFound(err error) error {
	if IsNotFound(err) {
		return nil
	}

	return err
}

func IsDeleteRepository(err error) bool {
	if err == nil {
		return false
	}

	errorResponse := new(client.ErrorResponse)
	ok := errors.As(err, &errorResponse)
	if !ok {
		return false
	}

	return newAPIError(errorResponse).Has(ErrDeleteRepository)
}
