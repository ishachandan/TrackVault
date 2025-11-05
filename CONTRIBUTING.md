# Contributing to TrackVault

Thank you for considering contributing to TrackVault! This document provides guidelines for contributing to the project.

## How to Contribute

### Reporting Bugs

If you find a bug, please open an issue with:
- Clear description of the bug
- Steps to reproduce
- Expected vs actual behavior
- System information (OS, Python version)
- Screenshots if applicable

### Suggesting Features

Feature requests are welcome! Please:
- Check if the feature already exists
- Clearly describe the feature and its benefits
- Explain the use case
- Consider implementation complexity

### Pull Requests

1. **Fork the repository**
2. **Create a feature branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

3. **Make your changes**
   - Write clean, readable code
   - Follow existing code style
   - Add comments for complex logic
   - Test your changes thoroughly

4. **Commit your changes**
   ```bash
   git commit -m "Add: brief description of changes"
   ```

5. **Push to your fork**
   ```bash
   git push origin feature/your-feature-name
   ```

6. **Open a Pull Request**
   - Describe what changes you made
   - Reference any related issues
   - Explain why the changes are needed

## Code Style Guidelines

### Python
- Follow PEP 8 style guide
- Use meaningful variable names
- Add docstrings to functions
- Keep functions focused and small
- Use type hints where appropriate

### JavaScript
- Use consistent indentation (2 or 4 spaces)
- Use meaningful variable names
- Add comments for complex logic
- Follow modern ES6+ practices

### HTML/CSS
- Use semantic HTML
- Keep CSS organized and modular
- Ensure responsive design
- Test across browsers

## Testing

Before submitting:
- Test the monitor service starts correctly
- Test the web interface loads properly
- Verify file monitoring works
- Check alert generation
- Test on a clean environment

## Development Setup

1. Clone your fork
2. Install dependencies: `pip install -r requirements.txt`
3. Make changes
4. Test thoroughly
5. Submit PR

## Areas for Contribution

- **Features**: New monitoring capabilities, dashboard features
- **UI/UX**: Improve design, add visualizations
- **Performance**: Optimize database queries, reduce memory usage
- **Documentation**: Improve guides, add examples
- **Testing**: Add unit tests, integration tests
- **Security**: Enhance security features, fix vulnerabilities
- **Cross-platform**: Linux/Mac support

## Questions?

Feel free to open an issue for any questions about contributing!

## Code of Conduct

- Be respectful and inclusive
- Welcome newcomers
- Focus on constructive feedback
- Help others learn and grow

Thank you for contributing! 🎉
