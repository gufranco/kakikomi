# Changelog

# [4.0.0](https://github.com/gufranco/kakikomi/compare/v3.0.0...v4.0.0) (2026-10-31)


* feat!: turn --release into the release command ([f71fee3](https://github.com/gufranco/kakikomi/commit/f71fee3742538b2ed695e613536352e8d7413634))


### Bug Fixes

* count dd bytes from its record counts ([9241d48](https://github.com/gufranco/kakikomi/commit/9241d488ca2b1f5ea2c6f8b3c9f8841367a0d7cf))
* read a BusyBox timeout 143 as a deadline ([9a83497](https://github.com/gufranco/kakikomi/commit/9a834976825ace3349271eb43ca86df5054aad8f))


### Features

* report a write as JSON with --json ([61276e1](https://github.com/gufranco/kakikomi/commit/61276e18dd29123253b3682124324bfa6e13fe53))
* use 7zz when 7z is not installed ([a456cb2](https://github.com/gufranco/kakikomi/commit/a456cb2903d6c25bad3cfa385a496b39b57d12e9))


### BREAKING CHANGES

* kakikomi --release is gone and fails as an unknown
option; run kakikomi release instead.

# [3.0.0](https://github.com/gufranco/kakikomi/compare/v2.2.0...v3.0.0) (2026-10-29)


* feat!: prefix every setting with KAKIKOMI_ ([513fe56](https://github.com/gufranco/kakikomi/commit/513fe568f3404054cedeac8bb4c161868cfc6160))


### Bug Fixes

* poll a bounded command within milliseconds ([2b8d386](https://github.com/gufranco/kakikomi/commit/2b8d386f0c2b476cb50017b290177917f52cd0b8))


### BREAKING CHANGES

* VERIFY, DELETE, AGAIN, REINSERT, ZERO_TAIL, SHA256,
ALLOW_INTERNAL, KEEP_GUARD, MODE and the tuning variables are no longer
read. Use their KAKIKOMI_ forms, such as KAKIKOMI_VERIFY.

# [2.2.0](https://github.com/gufranco/kakikomi/compare/v2.1.0...v2.2.0) (2026-10-28)


### Features

* check published checksums before writing ([f736bd8](https://github.com/gufranco/kakikomi/commit/f736bd873a2e10cfc7040e4e2fcfb675ecb2db87))

# [2.1.0](https://github.com/gufranco/kakikomi/compare/v2.0.0...v2.1.0) (2026-10-27)


### Features

* **cli:** follow the family command-line contract ([89cfdbe](https://github.com/gufranco/kakikomi/commit/89cfdbeb57485da62b00a698337bd0e1733908ae))
* **doctor:** name the flavor of each core tool ([af58c08](https://github.com/gufranco/kakikomi/commit/af58c083048afe3f1f91b95e6fa3f40b27a3f5d3))
* **source:** read a mounted volume as its disk ([05d333e](https://github.com/gufranco/kakikomi/commit/05d333e0a8f9842fca1188a0c514b36a381f12cd))

# [2.0.0](https://github.com/gufranco/kakikomi/compare/v1.0.0...v2.0.0) (2026-10-26)


* feat!: ship kiyome as its own project ([f30b4e0](https://github.com/gufranco/kakikomi/commit/f30b4e07dd39235558ae8e153468e7dac50df650))


### Bug Fixes

* **after:** find the trash command on the PATH ([5110a19](https://github.com/gufranco/kakikomi/commit/5110a19b51ba094d8b9287c98ac184d2b6d04de2))
* **after:** show the after-write questions ([dd3a81e](https://github.com/gufranco/kakikomi/commit/dd3a81ec0faf214c292bf72d172fe976ffdd8d13))
* **core:** see mounts on Linux partitions ([a08ee02](https://github.com/gufranco/kakikomi/commit/a08ee0272113214334ec4336e712e5513a913952))
* **guard:** lock fstab edits across workers ([be20c15](https://github.com/gufranco/kakikomi/commit/be20c15fec0ba7244eb911b0fa3f09810ead1b5d))
* **guard:** refuse APFS and HFS+ images again ([075e80b](https://github.com/gufranco/kakikomi/commit/075e80bbbc77daf7e5ae1bdccb0f68303d3da3af))
* **write:** judge no timing once a stop is pending ([0977d51](https://github.com/gufranco/kakikomi/commit/0977d51964b751026fe993cc4206692494a4b349))
* **write:** report a stop mid-transfer as one ([776732e](https://github.com/gufranco/kakikomi/commit/776732e95ab3b95060c86414b7aa9a97c4c0f2c6))
* **write:** watch for mounts only after unmounting ([068a60c](https://github.com/gufranco/kakikomi/commit/068a60cefc304d0d59c799638ea60c212054c8fa))


### Features

* **cli:** plain output, help, doctor and prompts ([8303e9a](https://github.com/gufranco/kakikomi/commit/8303e9aa54c876498006df3a086d8db47b221a7c))


### BREAKING CHANGES

* installing kakikomi no longer installs kiyome; install
gufranco/tap/kiyome for it.
