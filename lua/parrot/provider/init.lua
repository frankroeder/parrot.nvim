local Ollama = require("parrot.provider.ollama")
local OpenAI = require("parrot.provider.openai")
local Anthropic = require("parrot.provider.anthropic")
local Perplexity = require("parrot.provider.perplexity")

return {
	Ollama = Ollama,
	OpenAI = OpenAI,
	Anthropic = Anthropic,
	Perplexity = Perplexity,
}
