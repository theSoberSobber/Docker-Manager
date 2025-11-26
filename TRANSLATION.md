# Translation Guide

Docker Manager uses the `easy_localization` package for internationalization. Translation files are stored as JSON in the `assets/i18n/` directory.

## Adding a New Translation

### 1. Create Translation File

Create a new JSON file in `assets/i18n/` with the appropriate locale code:

- French: `fr.json`
- German: `de.json`
- Portuguese (Brazil): `pt-BR.json`
- Chinese (Simplified): `zh-CN.json`
- Japanese: `ja.json`
- Italian: `it.json`
- Russian: `ru.json`

### 2. Copy Base Structure

Use the English file as your template:

```bash
cp assets/i18n/en-US.json assets/i18n/YOUR-LOCALE.json
```

### 3. Translate All Values

Open your new file and translate only the values, keeping the keys unchanged:

```json
{
  "app": {
    "title": "Your Translation"
  },
  "common": {
    "cancel": "Your Translation",
    "delete": "Your Translation"
  }
}
```

**Important:**
- Keep `{}` placeholders intact (e.g., `"Selected server: {}"`)
- Maintain the nested JSON structure
- Translate values only, not keys
- Preserve technical terms where appropriate (Container, Docker, etc.)

### 4. Register Your Locale

Edit `lib/main.dart` and add your locale to the `supportedLocales` list:

```dart
supportedLocales: const [
  Locale('en', 'US'), 
  Locale('es'),
  Locale('fr'),  // Add your locale
],
```

### 5. Test Your Translation

When you open a Pull Request, GitHub Actions will automatically build an APK that you can download from the workflow artifacts to test your translation.

You can also test locally by running `flutter run` and changing your device language to the target locale.

## Translation File Structure

The JSON files use nested objects organized by feature:

- `app.*` - Application title
- `common.*` - Shared UI elements (buttons, statuses)
- `connection.*` - Server connection messages
- `navigation.*` - Bottom navigation labels
- `servers.*` - Server management
- `containers.*` - Container management
- `images.*` - Image management
- `volumes.*` - Volume management
- `networks.*` - Network management
- `system.*` - System information
- `settings.*` - Application settings

## Formatting Guidelines

- **Placeholders**: Use `{}` for dynamic values: `"Failed to connect to {}"`
- **Line breaks**: Use `\n` for new lines in multi-line strings
- **Tone**: Professional and friendly, matching the English version
- **Context**: Consider the UI context when translating button labels and error messages

## Submitting Your Translation

1. **Open an issue** to discuss the language you want to add
2. Fork the repository
3. Create a branch: `git checkout -b add-LANGUAGE-translation`
4. Add your translation file and update `lib/main.dart`
5. **Share your draft** in the issue for feedback
6. Submit a Pull Request (GitHub Actions will automatically build and validate)
   - Link to your discussion issue
   - Brief description of the language added

## Questions?

Open an issue if you need help with translations or have questions about specific terms.
