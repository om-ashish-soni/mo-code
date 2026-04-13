package tools

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"mo-code/backend/runtime"
)

const (
	// shellTimeout is the default maximum duration for a shell command.
	shellTimeout = 120 * time.Second
	// shellMaxTimeout is the hard upper limit.
	shellMaxTimeout = 600 * time.Second
	// shellMaxOutput is the maximum output size in bytes.
	shellMaxOutput = 100 * 1024 // 100KB
)

// ShellExec executes shell commands within the working directory.
// When a ProotRuntime is configured, commands are routed through proot + Alpine.
// When nil, commands execute directly on the host OS.
type ShellExec struct {
	workDir string
	proot   *runtime.ProotRuntime
}

// NewShellExec creates a ShellExec with direct host execution.
func NewShellExec(workDir string) *ShellExec {
	return &ShellExec{workDir: workDir}
}

// NewShellExecWithProot creates a ShellExec that routes commands through proot.
func NewShellExecWithProot(workDir string, proot *runtime.ProotRuntime) *ShellExec {
	return &ShellExec{workDir: workDir, proot: proot}
}

func (s *ShellExec) Name() string { return "shell_exec" }

func (s *ShellExec) Description() string {
	return "Execute a shell command. Returns stdout and stderr. " +
		"Default timeout: 120 seconds (max: 600). " +
		"Use for running builds, tests, linters, git commands, or inspecting the system. " +
		"Prefer grep/glob tools for file search instead of shell grep/find."
}

func (s *ShellExec) Parameters() string {
	return `{
		"type": "object",
		"properties": {
			"command": {
				"type": "string",
				"description": "The shell command to execute"
			},
			"description": {
				"type": "string",
				"description": "Brief description of what this command does (5-10 words)"
			},
			"timeout_seconds": {
				"type": "integer",
				"description": "Custom timeout in seconds. Default: 120, max: 600"
			},
			"working_dir": {
				"type": "string",
				"description": "Directory to run the command in (relative to project root). Default: project root"
			}
		},
		"required": ["command"]
	}`
}

func (s *ShellExec) Execute(ctx context.Context, argsJSON string) Result {
	var args struct {
		Command        string `json:"command"`
		Description    string `json:"description"`
		TimeoutSeconds int    `json:"timeout_seconds"`
		WorkingDir     string `json:"working_dir"`
	}
	if err := json.Unmarshal([]byte(argsJSON), &args); err != nil {
		return Result{Error: fmt.Sprintf("invalid arguments: %v", err), Output: fmt.Sprintf("Error: invalid arguments: %v", err)}
	}

	if args.Command == "" {
		return Result{Error: "command is required", Output: "Error: command is required"}
	}

	// Block obviously dangerous commands.
	if isDangerous(args.Command) {
		return Result{Error: fmt.Sprintf("command blocked for safety: %q", args.Command), Output: fmt.Sprintf("Error: command blocked for safety: %q", args.Command)}
	}

	timeout := shellTimeout
	if args.TimeoutSeconds > 0 {
		maxSec := int(shellMaxTimeout / time.Second)
		if args.TimeoutSeconds > maxSec {
			args.TimeoutSeconds = maxSec
		}
		timeout = time.Duration(args.TimeoutSeconds) * time.Second
	}

	cmdCtx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	// Resolve working directory — support relative paths.
	workDir := s.workDir
	if args.WorkingDir != "" {
		candidate := filepath.Join(s.workDir, args.WorkingDir)
		if abs, err := filepath.Abs(candidate); err == nil {
			workAbs, _ := filepath.Abs(s.workDir)
			if strings.HasPrefix(abs, workAbs) {
				workDir = abs
			}
		}
	}

	var stdoutStr, stderrStr string
	var exitCode int
	var runErr error

	if s.proot != nil {
		// Route through proot + Alpine.
		stdoutStr, stderrStr, exitCode, runErr = s.proot.Exec(cmdCtx, args.Command, workDir)
	} else {
		// Direct host execution.
		stdoutStr, stderrStr, exitCode, runErr = s.execDirect(cmdCtx, args.Command, workDir)
	}

	var sb strings.Builder

	if stdoutStr != "" {
		out := stdoutStr
		if len(out) > shellMaxOutput {
			out = out[:shellMaxOutput] + "\n... (output truncated)"
		}
		sb.WriteString(out)
	}

	if stderrStr != "" {
		errOut := stderrStr
		if len(errOut) > shellMaxOutput {
			errOut = errOut[:shellMaxOutput] + "\n... (stderr truncated)"
		}
		if sb.Len() > 0 {
			sb.WriteString("\n--- stderr ---\n")
		}
		sb.WriteString(errOut)
	}

	var errMsg string
	if runErr != nil {
		if cmdCtx.Err() == context.DeadlineExceeded {
			sb.WriteString(fmt.Sprintf("\n(command timed out after %s)", timeout))
			errMsg = "timeout"
		}
		if exitCode == 0 {
			exitCode = -1
		}
		sb.WriteString(fmt.Sprintf("\n(exit code: %d)", exitCode))
		if errMsg == "" {
			errMsg = fmt.Sprintf("exit code %d", exitCode)
		}
	} else if exitCode != 0 {
		sb.WriteString(fmt.Sprintf("\n(exit code: %d)", exitCode))
		errMsg = fmt.Sprintf("exit code %d", exitCode)
	}

	output := sb.String()
	if output == "" {
		output = "(no output)"
	}

	title := args.Description
	if title == "" {
		title = args.Command
		if len(title) > 60 {
			title = title[:60] + "..."
		}
	}

	return Result{
		Title:  title,
		Output: output,
		Error:  errMsg,
		Metadata: map[string]any{
			"command":   args.Command,
			"exit_code": exitCode,
			"runtime":   s.runtimeLabel(),
		},
	}
}

// execDirect runs a command directly on the host OS.
func (s *ShellExec) execDirect(ctx context.Context, command, workDir string) (stdout, stderr string, exitCode int, err error) {
	cmd := exec.CommandContext(ctx, "sh", "-c", command)
	cmd.Dir = workDir

	var outBuf, errBuf bytes.Buffer
	cmd.Stdout = &outBuf
	cmd.Stderr = &errBuf

	runErr := cmd.Run()
	exitCode = 0

	if runErr != nil {
		if exitErr, ok := runErr.(*exec.ExitError); ok {
			exitCode = exitErr.ExitCode()
		} else {
			exitCode = -1
			err = runErr
		}
	}

	return outBuf.String(), errBuf.String(), exitCode, err
}

// runtimeLabel returns "proot" or "host" for metadata.
func (s *ShellExec) runtimeLabel() string {
	if s.proot != nil {
		return "proot"
	}
	return "host"
}

// isDangerous returns true for commands that should never be run by an agent.
func isDangerous(cmd string) bool {
	lower := strings.ToLower(strings.TrimSpace(cmd))
	dangerous := []string{
		"rm -rf /",
		"rm -rf /*",
		"mkfs",
		"dd if=/dev/zero",
		":(){", // fork bomb
		"chmod -r 777",
		"> /dev/sda",
	}
	for _, d := range dangerous {
		if strings.Contains(lower, d) {
			return true
		}
	}
	return false
}
