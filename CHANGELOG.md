# Changelog

## [2.4.0](https://github.com/frankroeder/parrot.nvim/compare/v2.3.0...v2.4.0) (2025-09-30)


### Features

* add PrtReloadCache command to reload cached models ([10d146f](https://github.com/frankroeder/parrot.nvim/commit/10d146fba858b2e0c858ebbcddcd601ae6cb5e25))


### Bug Fixes

* addresses issue [#177](https://github.com/frankroeder/parrot.nvim/issues/177), reload list after deleting chat item ([708fccf](https://github.com/frankroeder/parrot.nvim/commit/708fccf259aab04cb5304802d00d03f437d74f4c))
* **logger:** stop overwriting global vim.notify function ([55676bc](https://github.com/frankroeder/parrot.nvim/commit/55676bce578969fce606bac04fefc27fd16e3a8a))
* remove chat prompt buffer, chats should be fully functional buffers ([da1eb03](https://github.com/frankroeder/parrot.nvim/commit/da1eb031ccb9d5822978d06f181b89e30cb66b81))
* rewrite, append and prepend now respect chat_free_cursor option ([6ad76a1](https://github.com/frankroeder/parrot.nvim/commit/6ad76a1b170b3fa49851504ab17cb39075b93b03))
* typos and correct chat/command mode detection ([8f97191](https://github.com/frankroeder/parrot.nvim/commit/8f9719188a5ce294c045a3973f83d7ee3a106277))

## [2.3.0](https://github.com/frankroeder/parrot.nvim/compare/v2.2.0...v2.3.0) (2025-07-15)


### Features

* make &lt;C-c&gt; cancel interactive rewrite/append/prepend commands ([7bc2dc1](https://github.com/frankroeder/parrot.nvim/commit/7bc2dc116e7541e5572e96010bd2b73b1c75dc34))
* preview (r)eject now jumps back to edit prompt and call API again ([621bd76](https://github.com/frankroeder/parrot.nvim/commit/621bd76108bfe83431612aed1abccca6fe1dcaea))


### Bug Fixes

* make preview (q)uit cancel the whole process ([1a8e3de](https://github.com/frankroeder/parrot.nvim/commit/1a8e3de0e4fd5d97766f2c8d99e76744334196ca))

## [2.2.0](https://github.com/frankroeder/parrot.nvim/compare/v2.1.0...v2.2.0) (2025-07-11)


### Features

* Add preview mode for interactive commands like rewrite/append/prepend ([#163](https://github.com/frankroeder/parrot.nvim/issues/163)) ([dcd58f9](https://github.com/frankroeder/parrot.nvim/commit/dcd58f9b1cff7890712760ad0b72a358a42d1a22))
* Improve spinner ([#165](https://github.com/frankroeder/parrot.nvim/issues/165)) ([66afa9c](https://github.com/frankroeder/parrot.nvim/commit/66afa9c460ddaa6f0bfe972f3795535d98911f35))

## [2.1.0](https://github.com/frankroeder/parrot.nvim/compare/v2.0.0...v2.1.0) (2025-05-31)


### Features

* **provider:** advanced model caching to prevent fetching models every time. ([07e22e2](https://github.com/frankroeder/parrot.nvim/commit/07e22e23203c81fd8100c8e630557436070a89fc))


### Bug Fixes

* **provider:** api_key command handle closing ([97dbbe1](https://github.com/frankroeder/parrot.nvim/commit/97dbbe1f90637c1cd895c07aff0cfd588f5a5e51))
* **provider:** model/models argument ([bcfb227](https://github.com/frankroeder/parrot.nvim/commit/bcfb227ffe3f9512fa198f12cf8fe38984a665cc))

## [2.0.0](https://github.com/frankroeder/parrot.nvim/compare/v1.8.0...v2.0.0) (2025-05-29)


### ⚠ BREAKING CHANGES

* add advanced and flexible provider configuration
* add advanced and flexible provider configuration

### Features

* add advanced and flexible provider configuration ([aabd7a5](https://github.com/frankroeder/parrot.nvim/commit/aabd7a5d629b26f765e84e06897bed861ba4a1c0))
* add advanced and flexible provider configuration ([bc70212](https://github.com/frankroeder/parrot.nvim/commit/bc702128e29985be9f85e73de4f7478ba95f52b8))

## [1.8.0](https://github.com/frankroeder/parrot.nvim/compare/v1.7.0...v1.8.0) (2025-05-27)


### Features

* Add PrtCmd to directly generate executable vim commands ([da3d5aa](https://github.com/frankroeder/parrot.nvim/commit/da3d5aa98f2077246bb36a3572a6d89825cd6cb8))


### Bug Fixes

* Directly pass prompt to PrtCmd and add readme hint, rm repo context ([e1a5f86](https://github.com/frankroeder/parrot.nvim/commit/e1a5f86a985f2e38ef0e1953565fe0308fcc3f7b))
* model selection with telescope in normal mode ([acfec2b](https://github.com/frankroeder/parrot.nvim/commit/acfec2bab4b6e5ab2c12f736fe74041b769be6c3))
* model selection with telescope in normal mode ([7dbf314](https://github.com/frankroeder/parrot.nvim/commit/7dbf314f40d9556974d8f5a7ab0cf3f015806696))

## [1.7.0](https://github.com/frankroeder/parrot.nvim/compare/v1.6.0...v1.7.0) (2025-04-10)


### Features

* add option to disable thinking window popping up ([afb8aab](https://github.com/frankroeder/parrot.nvim/commit/afb8aab69ef9b2b96dc89a198a49254db8a1909a))
* add predefined prompts for interactive commands ([42f3a8e](https://github.com/frankroeder/parrot.nvim/commit/42f3a8e5b72139f555a7698ecb5dc13a50afbbd2))
* **completion:** add globbing support ([@file](https://github.com/file):*.lua) ([c08b7e3](https://github.com/frankroeder/parrot.nvim/commit/c08b7e3aa9f6379c5d2462d9949bdaebcc2294d2))
* **provider:** add support for custom model selection ([55bd3f5](https://github.com/frankroeder/parrot.nvim/commit/55bd3f5b7c8d47fd45fd9b1d8a79f7e5d4b1872e))


### Bug Fixes

* add additional thinking check ([161e75e](https://github.com/frankroeder/parrot.nvim/commit/161e75e84019a63604944816d100d5601cf109bf))
* **context:** correct the location of expanding provided path ([074df4b](https://github.com/frankroeder/parrot.nvim/commit/074df4b580fc2de94712657d8a622d941170935b))
* remove stupid State argument ([2a5cdaf](https://github.com/frankroeder/parrot.nvim/commit/2a5cdaf3fd6db1a520b6b3e2bc44c33d0154c7e2))

## [1.6.0](https://github.com/frankroeder/parrot.nvim/compare/v1.5.0...v1.6.0) (2025-03-31)


### Features

* **finder:** Improve file search ([3158788](https://github.com/frankroeder/parrot.nvim/commit/3158788f52745310bee3ec5a53dd0012f17f34d0))


### Bug Fixes

* **openai:** check for reasoning models to change curl API parameters ([a2c9585](https://github.com/frankroeder/parrot.nvim/commit/a2c9585ba06a5f4794ca1ae14918b505700592f0))

## [1.5.0](https://github.com/frankroeder/parrot.nvim/compare/v1.4.0...v1.5.0) (2025-03-15)


### Features

* Add Claude thinking functionality ([f5a6057](https://github.com/frankroeder/parrot.nvim/commit/f5a6057a1a883fa979aacc6c04ecb8ea4dd2b128))
* **anthropic:** add auto scroll for thinking ([078e2eb](https://github.com/frankroeder/parrot.nvim/commit/078e2ebe5df88e6ffb2db6a9b592b4c4a4c72d96))
* Persist thinking config to state ([40597f9](https://github.com/frankroeder/parrot.nvim/commit/40597f9a605b35c984890677646fde29c4b83cec))
* Remember thinking config when toggling ([c92bdb9](https://github.com/frankroeder/parrot.nvim/commit/c92bdb93d3936f9b72fd80cbd3f94dededfebdfe))


### Bug Fixes

* pass payload to curl through stdin ([79446e2](https://github.com/frankroeder/parrot.nvim/commit/79446e2416fb81bf5cc478417c552ea17814d576))
* pass payload to curl through stdin ([5dd932e](https://github.com/frankroeder/parrot.nvim/commit/5dd932eb1146cf400880abb9bba437fe3dd2a1b7))

## [1.4.0](https://github.com/frankroeder/parrot.nvim/compare/v1.3.0...v1.4.0) (2025-03-11)


### Features

* add nvim-cmp context completion support ([8f9adc6](https://github.com/frankroeder/parrot.nvim/commit/8f9adc6096099da4a6290648457363a4e8bb13a6))


### Bug Fixes

* improve completion feature robustness and add tests ([9ad2ebc](https://github.com/frankroeder/parrot.nvim/commit/9ad2ebc9d93806b7195c27c01e480b01f8410ff6))

## [1.3.0](https://github.com/frankroeder/parrot.nvim/compare/v1.2.2...v1.3.0) (2025-03-06)


### Features

* add deepseek provider ([086ec4e](https://github.com/frankroeder/parrot.nvim/commit/086ec4e1f7bdf569f8e5f20104038ee80f9d5e75))
* add support to deepseek as a provider ([66da297](https://github.com/frankroeder/parrot.nvim/commit/66da297d328a90bbecfcb7c6302cce5246d60502))
* **anthropic:** add model request and update default model selection ([28113b9](https://github.com/frankroeder/parrot.nvim/commit/28113b9c7d23cebe54cfc9adac36aa613096e718))


### Bug Fixes

* **perplexity:** add new reasoning model ([340e195](https://github.com/frankroeder/parrot.nvim/commit/340e195fad6ae32576a2947d2af152b89bfc5344))
* **perplexity:** add new reasoning model ([7a87bab](https://github.com/frankroeder/parrot.nvim/commit/7a87bab9d9d37d00ff244bcd56cd1a9739692e30))
* **perplexity:** add the new reasoning pro model ([b5f37a0](https://github.com/frankroeder/parrot.nvim/commit/b5f37a07c76dba8ac1c8a34981af297067e69f64))
* **perplexity:** add the new reasoning pro model ([e5c2d94](https://github.com/frankroeder/parrot.nvim/commit/e5c2d9403fcdc6e9cb587eca099f442f109c9399))
* use new release-please repo ([4ac5422](https://github.com/frankroeder/parrot.nvim/commit/4ac542290c7b328e4a7916e7f6773d1a60c68957))

## [1.2.2](https://github.com/frankroeder/parrot.nvim/compare/v1.2.1...v1.2.2) (2025-01-26)


### Bug Fixes

* add missing module in mistral provider ([b8f52da](https://github.com/frankroeder/parrot.nvim/commit/b8f52dab988a2c21d18aff3ba7806ddc36c2fe8d))
* change current_provider default value to nil ([a8468be](https://github.com/frankroeder/parrot.nvim/commit/a8468be7311ac04b86bf08a05ea480f444b7c1ea))
* **perplexity:** update available models ([bdb30c2](https://github.com/frankroeder/parrot.nvim/commit/bdb30c2007f523e97911185ec97a55486adbecab))

## [1.2.1](https://github.com/frankroeder/parrot.nvim/compare/v1.2.0...v1.2.1) (2024-11-19)


### Bug Fixes

* Set filetype to markdown for parrot responses ([119828b](https://github.com/frankroeder/parrot.nvim/commit/119828b016c07c547a093fb31bf60272d518e033))
* use literal string compare before file deletion ([4d43901](https://github.com/frankroeder/parrot.nvim/commit/4d439010e6abf7bcb3e70761a3ccadaed19135ad))
* xAI API change of model listing request ([c992483](https://github.com/frankroeder/parrot.nvim/commit/c992483dd0cf9d7481b55714d52365d1f7a66f91))

## [1.2.0](https://github.com/frankroeder/parrot.nvim/compare/v1.1.0...v1.2.0) (2024-10-21)


### Features

* add xAI as provider for Grok ([ef0149d](https://github.com/frankroeder/parrot.nvim/commit/ef0149d4b335d83d79deacae2f4bbf10e78314f5))

## [1.1.0](https://github.com/frankroeder/parrot.nvim/compare/v1.0.0...v1.1.0) (2024-10-17)


### Features

* add nvidia api support ([94e218d](https://github.com/frankroeder/parrot.nvim/commit/94e218dee56344d065c9d0cf37d89225d03ae5f5))


### Bug Fixes

* resolve issue with toggle_target ([51e7d1c](https://github.com/frankroeder/parrot.nvim/commit/51e7d1c2820fb4333bdcfc9751abfa74e9d90329))

## [1.0.0](https://github.com/frankroeder/parrot.nvim/compare/v0.7.0...v1.0.0) (2024-10-15)


### ⚠ BREAKING CHANGES

* ChatNew now follows toggle_target option

### Features

* ChatNew now follows toggle_target option ([345fb4e](https://github.com/frankroeder/parrot.nvim/commit/345fb4e3bed17c1822c1cd40ccec158be13d3f7e))


### Bug Fixes

* **ollama:** additional guard if server is not running ([fdcaa6c](https://github.com/frankroeder/parrot.nvim/commit/fdcaa6ccc368b69f0b0cdd8d5998e53ac2812aeb))
* **provider:** remove pplx event-stream header ([b347a1c](https://github.com/frankroeder/parrot.nvim/commit/b347a1ce80336a519634df3668c8b940acf83653))
* resolve history bug with custom hooks ([0db1e3b](https://github.com/frankroeder/parrot.nvim/commit/0db1e3beff0c434fec13c809bd105a4485946ece))

## [0.7.0](https://github.com/frankroeder/parrot.nvim/compare/v0.6.0...v0.7.0) (2024-09-11)


### Features

* add github model beta support ([6f36955](https://github.com/frankroeder/parrot.nvim/commit/6f36955a2174af95c3cf98165e907cdf60f289bb))
* **provider:** add gemini online model support ([be975ee](https://github.com/frankroeder/parrot.nvim/commit/be975ee542c8c24ebb90f154e25e2c89633b5d2d))


### Bug Fixes

* add missing import ([4a50b58](https://github.com/frankroeder/parrot.nvim/commit/4a50b58ce0036009ffc7419df2c2619e8a09496e))
* **responsehandler:** address bug ([075294c](https://github.com/frankroeder/parrot.nvim/commit/075294c1a9da6e35727007c4105590b8768d3681))
* **responsehandler:** window handling ([f2cbfc5](https://github.com/frankroeder/parrot.nvim/commit/f2cbfc592e1a5c470a840abdba5abc4940911f55))

## [0.6.0](https://github.com/frankroeder/parrot.nvim/compare/v0.5.0...v0.6.0) (2024-08-22)


### Features

* add status line support ([3ac1d28](https://github.com/frankroeder/parrot.nvim/commit/3ac1d2885428a573b4851bbc07735465a2019351))
* **commands:** implement the retry command ([29f7701](https://github.com/frankroeder/parrot.nvim/commit/29f7701585e02abc363df0691c37f6699494bd03))


### Bug Fixes

* add `PrtStatus` command ([322a45e](https://github.com/frankroeder/parrot.nvim/commit/322a45ead223c4698f52ba5d03e745fe330a7ab5))
* add missing multifilecontent support for chat prompts ([b8f221e](https://github.com/frankroeder/parrot.nvim/commit/b8f221efdde7c0294917ecb96829e1e1fe6986b2))
* Neovim version check ([a4fd3f3](https://github.com/frankroeder/parrot.nvim/commit/a4fd3f3a55a258c689cd97f0b85a0f267bc239e3))
* revert wrong license change ([1a7192c](https://github.com/frankroeder/parrot.nvim/commit/1a7192c3842f55578f787ff08766d7d4e713f701))

## [0.5.0](https://github.com/frankroeder/parrot.nvim/compare/v0.4.2...v0.5.0) (2024-08-14)


### Features

* add option to toggle online model selection ([3f74c06](https://github.com/frankroeder/parrot.nvim/commit/3f74c06743ccbe200067892022fd84b908f3bce5))


### Bug Fixes

* add missing arguments to release-please ([70e7b06](https://github.com/frankroeder/parrot.nvim/commit/70e7b06cd9dc0fcf5cb6214402a5dd1bacf26661))
* extend permission of release worflow ([df22467](https://github.com/frankroeder/parrot.nvim/commit/df224670e5ee3e3a5c38e5de189112588455db11))
* typo ([edec3b1](https://github.com/frankroeder/parrot.nvim/commit/edec3b1740eac16fa3853fe2fb0d22c9f8095870))
* update pipeline ([917c102](https://github.com/frankroeder/parrot.nvim/commit/917c10276d5ce6ef1e93907e64b78003fb176eee))
* user_input_ui now supports the "buffer" option ([22abeb3](https://github.com/frankroeder/parrot.nvim/commit/22abeb3378b6c978a8fd7629a755e1af44d3f40c))
