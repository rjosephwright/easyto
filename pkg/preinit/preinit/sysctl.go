package preinit

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"

	"github.com/cloudboss/easyto/pkg/preinit/vmspec"
)

func keyToPath(key string) string {
	return filepath.Join("/proc/sys", strings.Replace(key, ".", "/", -1))
}

func sysctl(key, value string) error {
	procPath := keyToPath(key)
	f, err := os.OpenFile(procPath, os.O_RDWR, 0)
	if err != nil {
		return fmt.Errorf("unable to open %s: %w", procPath, err)
	}
	defer f.Close()
	_, err = f.Write([]byte(value))
	if err != nil {
		return fmt.Errorf("unable to write sysctl %s with value %s: %w", key, value, err)
	}
	return nil
}

func SetSysctls(sysctls vmspec.NameValueSource) error {
	wg := sync.WaitGroup{}
	lenSysctls := len(sysctls)
	wg.Add(lenSysctls)

	errC := make(chan error, lenSysctls)

	for _, sc := range sysctls {
		go func(sc vmspec.NameValue) {
			defer wg.Done()
			errC <- sysctl(sc.Name, sc.Value)
		}(sc)
	}

	wg.Wait()

	close(errC)

	var errs error
	for err := range errC {
		errs = errors.Join(errs, err)
	}
	return errs
}
