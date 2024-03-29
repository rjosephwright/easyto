package preinit

import (
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"

	yaml "github.com/goccy/go-yaml"
)

const (
	errorCodeBodyUnreadable = iota
	errorCodeInvalidMethod
	errorCodeInvalidURL
	errorCodeRequestError
	errorCodeStatusError
)

const (
	endpointMetadataDefault = "169.254.169.254"
)

type httpError struct {
	errorCode  int
	statusCode int
	url        string
	wrapped    error
}

func (h *httpError) Error() string {
	switch h.errorCode {
	case errorCodeInvalidMethod:
		return "invalid HTTP method"
	case errorCodeInvalidURL:
		return fmt.Errorf("invalid URL %s", h.url).Error()
	case errorCodeBodyUnreadable:
		return fmt.Errorf("unable to read response body: %w",
			h.wrapped).Error()
	case errorCodeRequestError:
		return fmt.Errorf("request error: %w", h.wrapped).Error()
	case errorCodeStatusError:
		return fmt.Errorf("request failed with status %s",
			http.StatusText(h.statusCode)).Error()
	default:
		return "unknown error making http request"
	}
}

func request(method string, requestURL string, header http.Header) (*http.Response, error) {
	u, err := url.Parse(requestURL)
	if err != nil {
		return nil, &httpError{errorCode: errorCodeInvalidURL, url: requestURL}
	}

	req := &http.Request{
		URL:    u,
		Header: header,
	}

	switch method {
	case "GET", "PUT":
		req.Method = method
	default:
		return nil, &httpError{errorCode: errorCodeInvalidMethod}
	}

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, &httpError{errorCode: errorCodeRequestError, wrapped: err}
	}

	if isErrorStatus(resp.StatusCode) {
		resp.Body.Close()
		return nil, &httpError{errorCode: errorCodeStatusError, statusCode: resp.StatusCode}
	}
	return resp, nil
}

func requestForString(method string, requestURL string, header http.Header) (string, error) {
	resp, err := request(method, requestURL, header)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", &httpError{errorCode: errorCodeBodyUnreadable, wrapped: err}
	}
	return string(body), nil
}

func getIMDSv2(path string, endpoint ...string) (*http.Response, error) {
	endpoint0 := endpointMetadataDefault
	if len(endpoint) > 0 {
		endpoint0 = endpoint[0]
	}

	tokenURL := &url.URL{Scheme: "http",
		Host: endpoint0,
		Path: "/latest/api/token",
	}
	token, err := requestForString("PUT", tokenURL.String(), http.Header{
		"X-aws-ec2-metadata-token-ttl-seconds": []string{"21600"},
	})
	if err != nil {
		return nil, fmt.Errorf("unable to get IMDSv2 token: %w", err)
	}

	pathURL := &url.URL{Scheme: "http",
		Host: endpoint0,
		Path: path,
	}
	return request("GET", pathURL.String(), http.Header{
		"X-aws-ec2-metadata-token": []string{token},
	})
}

func getUserData(endpoint ...string) (*VMSpec, error) {
	endpoint0 := endpointMetadataDefault
	if len(endpoint) > 0 {
		endpoint0 = endpoint[0]
	}

	vmspec := &VMSpec{}

	resp, err := getIMDSv2("/latest/user-data", endpoint0)
	if err != nil {
		// Return an empty VMSpec when no user data is defined.
		hErr := &httpError{}
		if errors.As(err, &hErr) && hErr.statusCode == http.StatusNotFound {
			fmt.Printf("Got http error %+v\n", hErr)
			return vmspec, nil
		} else {
			fmt.Printf("Got error %+v\n", err)
			return nil, err
		}
	}

	err = yaml.NewDecoder(resp.Body).Decode(vmspec)
	if err != nil {
		return nil, err
	}

	return vmspec, nil
}

func getRegion(endpoint ...string) (string, error) {
	endpoint0 := endpointMetadataDefault
	if len(endpoint) > 0 {
		endpoint0 = endpoint[0]
	}

	resp, err := getIMDSv2("/latest/meta-data/placement/region", endpoint0)
	if err != nil {
		return "", fmt.Errorf("unable to get region: %w", err)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", &httpError{errorCode: errorCodeBodyUnreadable, wrapped: err}
	}

	return string(body), nil
}

func isErrorStatus(status int) bool {
	return status >= http.StatusBadRequest
}
