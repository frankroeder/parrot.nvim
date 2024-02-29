local system_chat_prompt = [[
You are a versatile AI assistant with capabilities
extending to general knowledge and coding support. When engaging
with users, please adhere to the following guidelines to ensure
the highest quality of interaction:

- Admit when unsure by saying 'I don't know.'
- Ask for clarification when needed.
- Use first principles thinking to analyze queries.
- Start with the big picture, then focus on details.
- Apply the Socratic method to enhance understanding.
- Include all necessary code in your responses.
- Stay calm and confident with each task.
]]

local system_code_prompt = [[
You are an AI specializing in software development"
tasks, including code editing, completion, and debugging. Your
responses should strictly pertain to the code provided. Please ensure
that your reply is solely focused on the code snippet in question.
]]

local ollama_chat_agents = {
	{
		name = "Mistal-7B",
		model = { model = "mistral:latest", temperature = 1.5, top_p = 1, num_ctx = 8192, min_p = 0.05 },
		system_prompt = system_chat_prompt,
		provider = "ollama",
	},
	{
		name = "Llama-13B",
		model = { model = "llama2:13b", temperature = 1.5, top_p = 1, num_ctx = 8192, min_p = 0.05 },
		system_prompt = system_chat_prompt,
		provider = "ollama",
	},
	{
		name = "Gemma-2B",
		model = { model = "gemma:2b", temperature = 1.5, top_p = 1, num_ctx = 8192, min_p = 0.05 },
		system_prompt = system_chat_prompt,
		provider = "ollama",
	},
	{
		name = "Gemma-7B",
		model = { model = "gemma:7b", temperature = 1.5, top_p = 1, num_ctx = 8192, min_p = 0.05 },
		system_prompt = system_chat_prompt,
		provider = "ollama",
	},
}

local openai_chat_agents = {
	{
		name = "ChatGPT4",
		model = { model = "gpt-4-0125-preview", temperature = 1.1, top_p = 1 },
		system_prompt = system_chat_prompt,
		provider = "openai",
	},
	{
		name = "ChatGPT3.5",
		model = { model = "gpt-3.5-turbo-0125", temperature = 1.1, top_p = 1 },
		system_prompt = system_chat_prompt,
		provider = "openai",
	},
}

local pplx_chat_agents = {
	{
		name = "Perplexity-7B",
		model = { model = "pplx-7b-chat", temperature = 1.1, top_p = 1 },
		system_prompt = system_chat_prompt,
		provider = "pplx",
	},
	{
		name = "Perplexity-70B",
		model = { model = "pplx-70b-chat", temperature = 1.1, top_p = 1 },
		system_prompt = system_chat_prompt,
		provider = "pplx",
	},
	{
		name = "Perplexity-7B-Online",
		model = { model = "pplx-7b-online", temperature = 1.1, top_p = 1 },
		system_prompt = system_chat_prompt, -- ignored by online models
		provider = "pplx",
	},
	{
		name = "Perplexity-70B-Online",
		model = { model = "pplx-70b-online", temperature = 1.1, top_p = 1 },
		system_prompt = system_chat_prompt, -- ignored by online models
		provider = "pplx",
	},
	{
		name = "Llama2-70B",
		model = { model = "llama-2-70b-chat", temperature = 1.1, top_p = 1 },
		system_prompt = system_chat_prompt,
		provider = "pplx",
	},
	{
		name = "CodeLlama-34B",
		model = { model = "codellama-34b-instruct", temperature = 1.1, top_p = 1 },
		system_prompt = system_chat_prompt,
		provider = "pplx",
	},
	{
		name = "CodeLlama-70B",
		model = { model = "codellama-70b-instruct", temperature = 1.1, top_p = 1 },
		system_prompt = system_chat_prompt,
		provider = "pplx",
	},
	{
		name = "Mistral-7B",
		model = { model = "mistral-7b-instruct", temperature = 1.1, top_p = 1 },
		system_prompt = system_chat_prompt,
		provider = "pplx",
	},
	{
		name = "Mistral-8x7B",
		model = { model = "mixtral-8x7b-instruct", temperature = 1.1, top_p = 1 },
		system_prompt = system_chat_prompt,
		provider = "pplx",
	},
}

local ollama_command_agents = {
	{
		name = "Mistal-7B",
		model = { model = "mistral:latest", temperature = 1.5, top_p = 1, num_ctx = 8192, min_p = 0.05 },
		system_prompt = system_code_prompt,
		provider = "ollama",
	},
	{
		name = "Llama-13B",
		model = { model = "llama2:13b", temperature = 1.5, top_p = 1, num_ctx = 8192, min_p = 0.05 },
		system_prompt = system_code_prompt,
		provider = "ollama",
	},
	{
		name = "Gemma-2B",
		model = { model = "gemma:2b", temperature = 1.5, top_p = 1, num_ctx = 8192, min_p = 0.05 },
		system_prompt = system_code_prompt,
		provider = "ollama",
	},
	{
		name = "Gemma-7B",
		model = { model = "gemma:7b", temperature = 1.5, top_p = 1, num_ctx = 8192, min_p = 0.05 },
		system_prompt = system_code_prompt,
		provider = "ollama",
	},
}

local openai_command_agents = {
	{
		name = "CodeGPT4",
		model = { model = "gpt-4-0125-preview", temperature = 1.1, top_p = 1 },
		system_prompt = system_code_prompt,
		provider = "openai",
	},
	{
		name = "CodeGPT3.5",
		model = { model = "gpt-3.5-turbo-0125", temperature = 1.1, top_p = 1 },
		system_prompt = system_code_prompt,
		provider = "openai",
	},
}

local pplx_command_agents = {
	{
		name = "Perplexity-7B",
		model = { model = "pplx-7b-chat", temperature = 0.8, top_p = 1 },
		system_prompt = system_code_prompt,
		provider = "pplx",
	},
	{
		name = "Perplexity-70B",
		model = { model = "pplx-70b-chat", temperature = 0.8, top_p = 1 },
		system_prompt = system_code_prompt,
		provider = "pplx",
	},
	{
		name = "Perplexity-7B-Online",
		model = { model = "pplx-7b-online", temperature = 0.8, top_p = 1 },
		system_prompt = system_code_prompt, -- ignored by online models
		provider = "pplx",
	},
	{
		name = "Perplexity-70B-Online",
		model = { model = "pplx-70b-online", temperature = 0.8, top_p = 1 },
		system_prompt = system_code_prompt, -- ignored by online models
		provider = "pplx",
	},
	{
		name = "Llama2-70B",
		model = { model = "llama-2-70b-chat", temperature = 0.8, top_p = 1 },
		system_prompt = system_code_prompt,
		provider = "pplx",
	},
	{
		name = "CodeLlama-34B",
		model = { model = "codellama-34b-instruct", temperature = 0.8, top_p = 1 },
		system_prompt = system_code_prompt,
		provider = "pplx",
	},
	{
		name = "CodeLlama-70B",
		model = { model = "codellama-70b-instruct", temperature = 0.8, top_p = 1 },
		system_prompt = system_code_prompt,
		provider = "pplx",
	},
	{
		name = "Mistral-7B",
		model = { model = "mistral-7b-instruct", temperature = 0.8, top_p = 1 },
		system_prompt = system_code_prompt,
		provider = "pplx",
	},
	{
		name = "Mistral-8x7B",
		model = { model = "mixtral-8x7b-instruct", temperature = 0.8, top_p = 1 },
		system_prompt = system_code_prompt,
		provider = "pplx",
	},
}

local M = {}

M.chat_agents = {}
for _, agent in ipairs(ollama_chat_agents) do
	table.insert(M.chat_agents, agent)
end

for _, agent in ipairs(openai_chat_agents) do
	table.insert(M.chat_agents, agent)
end
for _, agent in ipairs(pplx_chat_agents) do
	table.insert(M.chat_agents, agent)
end

M.command_agents = {}
for _, agent in ipairs(ollama_command_agents) do
	table.insert(M.command_agents, agent)
end
for _, agent in ipairs(openai_command_agents) do
	table.insert(M.command_agents, agent)
end
for _, agent in ipairs(pplx_command_agents) do
	table.insert(M.command_agents, agent)
end
return M
