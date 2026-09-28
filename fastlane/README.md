fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios latest_build

```sh
[bundle exec] fastlane ios latest_build
```

Show the latest TestFlight build number for version 2.0.1

### ios beta

```sh
[bundle exec] fastlane ios beta
```

Build and upload Wamori to TestFlight

### ios release_screenshots

```sh
[bundle exec] fastlane ios release_screenshots
```

Upload the prepared App Store screenshots for version 2.0.1

### ios submit_review

```sh
[bundle exec] fastlane ios submit_review
```

Submit Wamori 2.0.1 (build 13) for review and reset the summary rating

### ios release_precheck

```sh
[bundle exec] fastlane ios release_precheck
```

Validate Wamori App Store metadata before review submission

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
