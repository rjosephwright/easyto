package tree

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"os/user"
	"path/filepath"
	"strings"

	"github.com/cloudboss/easyto/pkg/constants"
	"github.com/cloudboss/easyto/pkg/initial/vmspec"
	"github.com/spf13/cobra"
)

var (
	amiCfg = &amiConfig{}
	amiCmd = &cobra.Command{
		Use:   "ami",
		Short: "Convert a container image to an EC2 AMI",
		PreRunE: func(cmd *cobra.Command, args []string) error {
			cmd.SilenceUsage = true

			assetDir, err := expandPath(amiCfg.assetDir)
			if err != nil {
				return fmt.Errorf("failed to expand asset directory path: %w", err)
			}
			amiCfg.assetDir = assetDir

			return vmspec.ValidateServices(amiCfg.services)
		},
		RunE: func(cmd *cobra.Command, args []string) error {
			quotedServices := bytes.NewBufferString("")
			err := json.NewEncoder(quotedServices).Encode(amiCfg.services)
			if err != nil {
				// Unlikely that []string cannot be encoded to JSON, but check anyway.
				return fmt.Errorf("unexpected value for services: %w", err)
			}

			packerArgs := []string{
				"build",
				"-var", fmt.Sprintf("ami_name=%s", amiCfg.amiName),
				"-var", fmt.Sprintf("asset_dir=%s", amiCfg.assetDir),
				"-var", fmt.Sprintf("container_image=%s", amiCfg.containerImage),
				"-var", fmt.Sprintf("debug=%t", amiCfg.debug),
				"-var", fmt.Sprintf("login_user=%s", amiCfg.loginUser),
				"-var", fmt.Sprintf("login_shell=%s", amiCfg.loginShell),
				"-var", fmt.Sprintf("root_device_name=%s", amiCfg.rootDeviceName),
				"-var", fmt.Sprintf("root_vol_size=%d", amiCfg.size),
				"-var", fmt.Sprintf("services=%s", quotedServices.String()),
				"-var", fmt.Sprintf("subnet_id=%s", amiCfg.subnetID),
				"build.pkr.hcl",
			}

			packer := exec.Command("./packer", packerArgs...)

			packer.Stdin = os.Stdin
			packer.Stdout = os.Stdout
			packer.Stderr = os.Stderr

			packer.Dir = amiCfg.packerDir

			packer.Env = append(os.Environ(), []string{
				"CHECKPOINT_DISABLE=1",
				fmt.Sprintf("PACKER_PLUGIN_PATH=%s/plugins", amiCfg.packerDir),
			}...)

			if amiCfg.debug {
				fmt.Printf("%+v\n", packer)
			}

			cmd.SilenceUsage = true

			return packer.Run()
		},
	}
)

type amiConfig struct {
	amiName        string
	assetDir       string
	containerImage string
	debug          bool
	loginUser      string
	loginShell     string
	packerDir      string
	rootDeviceName string
	services       []string
	size           int
	subnetID       string
}

func init() {
	rootCmd.AddCommand(amiCmd)

	this, err := os.Executable()
	if err != nil {
		panic(err)
	}
	assetDirRequired := false
	assetDir, err := filepath.Abs(filepath.Join(filepath.Dir(this), "..", "assets"))
	if err != nil {
		assetDirRequired = true
	}

	packerDir, err := filepath.Abs(filepath.Join(filepath.Dir(this), "..", "packer"))
	if err != nil {
		panic(err)
	}
	amiCfg.packerDir = packerDir

	amiCmd.Flags().StringVarP(&amiCfg.amiName, "ami-name", "a", "", "Name of the AMI.")
	amiCmd.MarkFlagRequired("ami-name")

	amiCmd.Flags().StringVarP(&amiCfg.assetDir, "asset-directory", "A", assetDir,
		"Path to a directory containing asset files.")
	if assetDirRequired {
		amiCmd.MarkFlagRequired("asset-directory")
	}

	amiCmd.Flags().StringVarP(&amiCfg.containerImage, "container-image", "c", "",
		"Name of the container image.")
	amiCmd.MarkFlagRequired("container-image")

	amiCmd.Flags().IntVarP(&amiCfg.size, "size", "S", 10,
		"Size of the image root volume in GB.")

	amiCmd.Flags().StringVar(&amiCfg.loginUser, "login-user", "cloudboss",
		"Login user to create in the VM image if ssh service is enabled.")

	loginShell := filepath.Join(constants.DirETBin, "sh")
	amiCmd.Flags().StringVar(&amiCfg.loginShell, "login-shell", loginShell,
		"Shell to use for the login user if ssh service is enabled.")

	amiCmd.Flags().StringVar(&amiCfg.rootDeviceName, "root-device-name", "/dev/xvda",
		"Name of the AMI root device.")

	amiCmd.Flags().StringVarP(&amiCfg.subnetID, "subnet-id", "s", "",
		"ID of the subnet in which to run the image builder.")
	amiCmd.MarkFlagRequired("subnet-id")

	amiCmd.Flags().StringSliceVar(&amiCfg.services, "services", []string{"chrony"},
		"Comma separated list of services to enable [chrony,ssh]. Use an empty string to disable all services.")

	amiCmd.Flags().BoolVar(&amiCfg.debug, "debug", false,
		"Whether or not to enable debug output.")
}

func expandPath(pth string) (string, error) {
	if strings.HasPrefix(pth, "~/") {
		me, err := user.Current()
		if err != nil {
			return "", err
		}
		fields := strings.Split(pth, string(filepath.Separator))
		newFields := []string{me.HomeDir}
		newFields = append(newFields, fields[1:]...)
		return filepath.Join(newFields...), nil
	}

	return pth, nil
}
