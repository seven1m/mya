# Amazon Q Developer Rules for Mya Compiler Project

## Project Overview
This is a Ruby-based compiler project called "Mya" that compiles a statically-typed subset of Ruby to LLVM IR. The project is experimental and focuses on type systems, type inference, and compiler construction.

## Architecture
- **Compiler**: Main compilation pipeline using Prism parser
- **TypeChecker**: Constraint solver
- **VM**: Virtual machine for executing compiled code
- **Instructions**: Intermediate representation for compiled code
- **Backends**: Code generation (currently LLVM)

## Code Style and Standards

### Ruby Style
- Use **SyntaxTree** formatter with 120 character line width
- Single quotes preferred over double quotes
- Trailing commas enabled in collections
- No auto-ternary operators
- 2-space indentation for Ruby files
- 4-space indentation for C/C++ files

### Type System Conventions
- Use Ruby terminology: "methods" not "functions"
- Type representations: `([(param_types)] -> return_type)`
- Concrete types: simple names (int, str, bool, nil)
- Object types: `(object ClassName)`
- Method types: `([(receiver, params)] -> return_type)`

### Testing
- Use Minitest with spec-style syntax
- Custom `must_equal_with_diff` matcher for complex comparisons
- Test files end with `_spec.rb`
- Use descriptive test names: `'compiles method definitions'`
- Group related tests in describe blocks

### Comments
- Avoid comments that just explain what code does
- Use comments for complex algorithms or non-obvious decisions
- Document public APIs and class purposes
- Prefer self-documenting code over comments

### File Organization
- `lib/mya/` - Main library code
- `lib/mya/compiler/` - Compiler components
- `spec/` - Test files
- `examples/` - Example Mya programs
- `src/` - C code for runtime

### Dependencies
- **Prism**: Ruby parser
- **ruby-llvm**: LLVM bindings
- **Minitest**: Testing framework
- **SyntaxTree**: Code formatting

### Development Workflow
- Use `bundle exec rake spec` to run tests
- Use `bundle exec rake lint` for style checking
- Use `bundle exec rake watch` for continuous testing
- Docker support available for consistent environments

## CLI Usage for Debugging and Inspection

The `bin/mya` binary provides options for examining compiler output and executing code:

### Basic Usage
```bash
# Execute code with LLVM backend (default)
./bin/mya -e "1 + 2"
./bin/mya examples/fact.rb

# Show help
./bin/mya --help
```

### Debug Output
```bash
# Show compiled instructions (our compiler IR)
./bin/mya -d ir -e "def add(a, b); a + b; end; add(1, 2)"

# Show generated LLVM IR
./bin/mya -d llvm-ir -e "1 + 2"

# Write LLVM IR to file using shell redirection
./bin/mya -d llvm-ir examples/fact.rb > output.ll
```

### Backend Selection
```bash
# Execute with LLVM backend (default)
./bin/mya --backend llvm examples/fact.rb

# Execute with VM backend
./bin/mya --backend vm examples/fact.rb
```

### Available Options
- `-e CODE` - Execute code string
- `-d DEBUG` - Show debug output (ir, llvm-ir) - does not execute code
- `--backend BACKEND` - Execute with specified backend (vm, llvm)
- `-h, --help` - Show help

### Examples
```bash
# Quick instruction inspection
./bin/mya -d ir -e "1 + 2"

# Generate LLVM IR file for analysis
./bin/mya -d llvm-ir examples/countdown.rb > analysis.ll

# Execute with specific backend
./bin/mya --backend vm examples/fact.rb
```
