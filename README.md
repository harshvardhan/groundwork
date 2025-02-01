# groundwork

Extract contextual foundations from your codebase for debugging and LLM interactions. Build solid ground for code understanding.

## 🎯 Why Groundwork?

Like a solid foundation is crucial for building, proper context is essential for understanding code. Groundwork helps you:
- Build consolidated views of your code modules
- Map code dependencies and relationships
- Create rich context for LLM interactions
- Support efficient debugging workflows

## ⚡ Key Features

- **Context Builder**: Consolidate relevant source files into clear, organized snapshots
- **Dependency Mapper**: Trace code relationships from any starting point
- **Smart Filtering**: Focus on relevant code by excluding build files, tests, and generated code
- **Performance Focused**: Handle large codebases efficiently with memory management and caching
- **Cross-Platform**: Works seamlessly on Linux, macOS, and Unix-like systems
- **LLM-Optimized**: Generate context in formats that work naturally with LLMs

## Installation

```bash
# Clone the repository
git clone https://github.com/yourusername/groundwork
cd groundwork

# Make scripts executable
chmod +x scripts/*.sh
```

## Quick Start

### Building Context
```bash
./scripts/build_context.sh <module_directory_path>
```

### Mapping Dependencies
```bash
./scripts/map_dependencies.sh <project_root> <entry_file> [max_depth]
```

For more detailed examples, see [examples](examples/).

## Contributing

Contributions are welcome! See our [Contributing Guidelines](docs/contributing.md) for details on how to get started.

## License

MIT License - see [LICENSE](LICENSE) for details.