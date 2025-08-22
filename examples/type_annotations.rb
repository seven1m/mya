class Person
  def initialize(name, age, active) # name:String, age:Integer, active:Boolean
    @name = name # @name:String
    @age = age # @age:Integer
    @active = active # @active:Boolean
    @score = 0 # @score:Integer
  end

  def name
    @name
  end

  def age
    @age
  end

  def active=(active)
    @active = active
  end

  def active
    @active
  end

  def score
    @score
  end

  def add_points(points) # points:Integer
    @score = @score + points
  end

  def info
    @name + ' is ' + @age.to_s + ' years old with ' + @score.to_s + ' points (active: ' + @active.to_s + ')'
  end
end

def process_data
  count = 5 # count:Integer
  message = 'Count is: ' # message:String
  finished = true # finished:Boolean

  count = count * 2
  message = message + count.to_s

  puts message
  puts 'Finished: ' + finished.to_s
  count
end

def add_numbers(x, y) # x:Integer, y:Integer
  puts 'Adding ' + x.to_s + ' and ' + y.to_s
  x + y
end

def greet_person(name) # name:String
  puts 'Hello, ' + name + '!'
  name
end

def check_status(active) # active:Boolean
  puts 'Status is: ' + active.to_s
  active
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
