# Claude Terminal for Home Assistant (Enhanced Fork)

This repository is an enhanced fork of the original [heytcass/home-assistant-addons](https://github.com/heytcass/home-assistant-addons) with significant improvements for authentication persistence and session management.

## 🚀 Enhanced Features (v1.2.0)

### ✅ **Authentication Persistence** 
- **No more repeated logins!** Authentication now persists across container restarts
- Automatic credential backup and restoration
- Background credential monitoring service

### ✅ **Transparent Session Management**
- **Resume exactly where you left off** when reconnecting
- Automatic tmux session creation and restoration
- Close browser, come back later, continue your work seamlessly
- No manual tmux commands required - completely transparent

### ✅ **Advanced Terminal Tools**
- Pre-installed `tmux` and `screen` for power users
- Background process support with `nohup`
- Persistent terminal multiplexer sessions

## Installation

To add this **enhanced repository** to your Home Assistant instance:

1. Go to **Settings** → **Add-ons** → **Add-on Store**
2. Click the three dots menu in the top right corner
3. Select **Repositories**
4. Add the URL: `https://github.com/Maheidem/home-assistant-addons`
5. Click **Add**

## Add-ons

### Claude Terminal (Enhanced)

A web-based terminal interface with Claude Code CLI pre-installed, now with persistent authentication and transparent session management. This add-on provides a seamless terminal environment directly in your Home Assistant dashboard.

#### Core Features:
- **Web terminal access** through your Home Assistant UI
- **Pre-installed Claude Code CLI** with automatic session management
- **Persistent authentication** - login once, stay logged in
- **Transparent session persistence** - resume work after browser close
- **Direct access** to your Home Assistant config directory
- **OAuth integration** with automatic credential management

#### Advanced Features:
- **Background credential monitoring** - automatic auth backup
- **tmux/screen support** - for advanced terminal workflows  
- **Long-running command support** - processes survive disconnection
- **Automatic session restoration** - seamless reconnection experience

#### Configuration Options:
- **Auto-launch Claude** - Automatically start Claude on terminal open
- **Persistent Sessions** - Enable transparent session management (recommended)

#### Use Cases:
- **Code generation and explanation** with persistent context
- **Debugging assistance** across multiple sessions
- **Home Assistant automation development** with saved progress
- **Long-running AI tasks** that survive browser disconnection

[Documentation](claude-terminal/DOCS.md)

## Support

If you have any questions or issues with this enhanced add-on, please create an issue in this repository.

## Credits & Acknowledgments

### 🙏 **Original Work**
This repository is a fork of [heytcass/home-assistant-addons](https://github.com/heytcass/home-assistant-addons). Full credit and appreciation to **heytcass** for creating the original Claude Terminal add-on that made this project possible.

### 🤖 **AI-Assisted Development**
The original add-on and these enhancements were created with the assistance of **Anthropic's Claude Code CLI**! The entire development process, debugging, feature implementation, and documentation were completed using Claude's AI capabilities - a true example of AI helping to improve AI tools.

### 🚀 **Enhancement Contributions**
- **Authentication Persistence System** - Resolved the "pain in the ass" repeated login issue
- **Transparent Session Management** - Seamless session restoration with tmux integration  
- **Background Credential Monitoring** - Automatic auth backup and restoration
- **Advanced Terminal Tools** - tmux, screen, and persistent session support
- **Enhanced Documentation** - Comprehensive guides and troubleshooting

### 🔄 **Fork Relationship**
- **Upstream**: [heytcass/home-assistant-addons](https://github.com/heytcass/home-assistant-addons)
- **Enhanced Fork**: [Maheidem/home-assistant-addons](https://github.com/Maheidem/home-assistant-addons)

## Contributing

Feel free to contribute improvements back to this fork! For issues with the core add-on functionality, consider contributing to the original repository as well.

## License

This repository maintains the same license as the original work - MIT License. See the [LICENSE](LICENSE) file for details.
