local class = require "lib.class"

--- @class AverageValueDefinition : ClassDefinition
local AverageValue = class.class("AverageValue")

--- [override] Creates a new AverageValue instance with the given length
--- @param length integer  The number of values to average over
--- @return AverageValue
function AverageValue:new(length)
    --- @class AverageValue : ClassInstance
    local instance = AverageValue:create_instance(length)

    --- @private
    --- The number of values to average over
    instance.length = length
    --- @private
    --- @type number[] A cyclical buffer containing the recorded values
    instance.values = {}
    --- @private
    --- @type number  The calculated average of the values in the buffer
    instance.__average = 0
    --- @private
    --- @type boolean  Whether the buffer has been updated since the last time the average was calculated
    instance.__dirty = false
    --- @private
    --- @type number  The current index in the values table to write to
    instance.__head = 1

    function instance:clear()
        self.values = {}
        self.__average = 0
        self.__dirty = false
        self.__head = 1
    end

    --- Adds the value to the current buffer, overwriting the oldest value if the buffer is full
    --- @param value number  The value to add to the buffer
    function instance:measure(value)
        if #self.values < self.length then
            table.insert(self.values, value)
            self.__head = #self.values + 1
        else
            self.values[self.__head] = value
            self.__head = self.__head > self.length and 1 or self.__head + 1
        end
        self.__dirty = true
    end

    --- Gets the average of the measured values
    --- @return number
    function instance:get()
        if #self.values == 0 then return 0 end
        if self.__dirty then
            local sum = 0
            for _, value in ipairs(self.values) do sum = sum + value end
            self.__average = sum / #self.values
            self.__dirty = false
        end
        return self.__average
    end

    return instance
end

return {
    class = {
        AverageValue = AverageValue
    }
}