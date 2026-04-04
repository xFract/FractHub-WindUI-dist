local Maid = {}
Maid.__index = Maid

function Maid.new()
	return setmetatable({
		_tasks = {},
	}, Maid)
end

function Maid:GiveTask(task)
	if not task then
		error("Task cannot be false or nil", 2)
	end

	local taskId = #self._tasks + 1
	self._tasks[taskId] = task
	return taskId
end

function Maid:DoCleaning()
	local tasks = self._tasks
	for index, task in pairs(tasks) do
		if typeof(task) == "RBXScriptConnection" then
			task:Disconnect()
		elseif type(task) == "function" then
			task()
		elseif typeof(task) == "Instance" then
			task:Destroy()
		elseif type(task) == "table" and type(task.Destroy) == "function" then
			task:Destroy()
		elseif type(task) == "table" and type(task.DoCleaning) == "function" then
			task:DoCleaning()
		end

		tasks[index] = nil
	end
end

function Maid:Destroy()
	self:DoCleaning()
end

return Maid
