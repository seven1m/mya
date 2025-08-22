class Person
  def initialize(name, age, active) # name:String, age:Integer, active:Boolean
    @name = name # @name:String
    @age = age # @age:Integer
    @active = active # @active:Boolean
    @score = 0 # @score:Integer
  end

  def name # -> String
    @name
  end

  def age # -> Integer
    @age
  end

  def active=(active) # active:Boolean
    @active = active
  end

  def active # -> Boolean
    @active
  end

  def score # -> Integer
    @score
  end

  def add_points(points) # points:Integer -> Integer
    @score = @score + points
  end

  def info # -> String
    @name + ' is ' + @age.to_s + ' years old with ' + @score.to_s + ' points (active: ' + @active.to_s + ')'
  end
end

def process_data # -> Integer
  count = 5 # count:Integer
  message = 'Count is: ' # message:String
  finished = true # finished:Boolean

  count = count * 2
  message = message + count.to_s

  puts message
  puts 'Finished: ' + finished.to_s
  count
end

def add_numbers(x, y) # x:Integer, y:Integer -> Integer
  puts 'Adding ' + x.to_s + ' and ' + y.to_s
  x + y
end

def greet_person(name) # name:String -> String
  puts 'Hello, ' + name + '!'
  name
end

def check_status(active) # active:Boolean -> Boolean
  puts 'Status is: ' + active.to_s
  active
end

def get_greeting # -> String
  "Welcome to Mya!"
end

def maybe_process(value) # value:Option[String] -> String
  if value
    "Processed: " + value.value!
  else
    "Nothing to process"
  end
end

person = Person.new('Alice', 25, false)
puts person.info

person.active = true
person.add_points(100)
puts person.info

sum = add_numbers(10, 20)
puts 'Sum: ' + sum.to_s

greeting = greet_person('Bob')
puts 'Greeted: ' + greeting

status = check_status(false)
puts 'Final status: ' + status.to_s

puts get_greeting

result1 = maybe_process("data")
result2 = maybe_process(nil)
puts result1
puts result2
