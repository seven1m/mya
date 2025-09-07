require 'bundler/setup'
require 'prism'
require_relative 'compiler/instruction'
require_relative 'compiler/type_checker'
require_relative 'compiler/backends/llvm_backend'
require_relative 'compiler/backends/vm_backend'

class Compiler
  def initialize(code)
    @code = code
    @result = Prism.parse(code)
    @ast = @result.value
    @directives =
      @result
        .comments
        .each_with_object({}) do |comment, directives|
          text = comment.location.slice
          line = comment.location.start_line
          directives[line] ||= {}

          # Parse type annotations like "a:Integer, b:String"
          if text =~ /#\s*(.+)/
            annotation_text = $1.strip
            type_annotations = parse_type_annotations(annotation_text)
            directives[line][:type_annotations] = type_annotations unless type_annotations.empty?
          end

          # Parse existing directives
          text.split.each do |directive|
            next unless directive =~ /^([a-z][a-z_]*):([a-z_]+)$/

            directives[line][$1.to_sym] ||= []
            directives[line][$1.to_sym] << $2.to_sym
          end
        end
  end

  def parse_type_annotations(text)
    return {} if text.nil? || text.strip.empty?
    TypeAnnotationParser.new(text).parse
  end

  class TypeAnnotationParser
    def initialize(text)
      @text = text.strip
      @pos = 0
    end

    def parse
      annotations = {}
      return annotations if @text.empty?
      
      # Parse parameters
      while @pos < @text.length && !peek_return_arrow?
        skip_whitespace
        break if @pos >= @text.length || peek_return_arrow?
        
        # If we can't parse a variable name, we're done with parameters
        break unless can_parse_variable_name?
        
        var_name = parse_variable_name
        skip_whitespace
        
        # If no colon follows, this isn't a type annotation
        break unless peek(':')
        
        expect(':')
        skip_whitespace
        type_spec = parse_type_spec
        
        annotations[var_name.to_sym] = type_spec
        
        skip_whitespace
        if peek(',')
          consume(',')
          skip_whitespace
        end
      end
      
      # Parse return type
      if peek_return_arrow?
        consume('-')
        consume('>')
        skip_whitespace
        annotations[:return_type] = parse_type_spec
      end
      
      annotations
    end

    private

    def can_parse_variable_name?
      saved_pos = @pos
      consume('@') if peek('@')
      result = peek(/[a-zA-Z_]/)
      @pos = saved_pos
      result
    end

    def parse_variable_name
      start = @pos
      consume('@') if peek('@')
      
      unless peek(/[a-zA-Z_]/)
        raise "Expected variable name at position #{@pos}"
      end
      
      while peek(/[a-zA-Z0-9_]/)
        @pos += 1
      end
      
      @text[start...@pos]
    end

    def parse_type_spec
      type_name = parse_identifier
      
      if peek('[')
        consume('[')
        skip_whitespace
        inner_type = parse_type_spec
        skip_whitespace
        expect(']')
        { generic: type_name.to_sym, inner: inner_type }
      else
        type_name.to_sym
      end
    end

    def parse_identifier
      start = @pos
      
      unless peek(/[a-zA-Z]/)
        raise "Expected identifier at position #{@pos}"
      end
      
      while peek(/[a-zA-Z0-9_]/)
        @pos += 1
      end
      
      @text[start...@pos]
    end

    def peek(pattern = nil)
      return false if @pos >= @text.length
      
      if pattern.is_a?(Regexp)
        @text[@pos] =~ pattern
      elsif pattern.is_a?(String)
        @text[@pos...@pos + pattern.length] == pattern
      else
        @text[@pos]
      end
    end

    def peek_return_arrow?
      peek('-') && @pos + 1 < @text.length && @text[@pos + 1] == '>'
    end

    def consume(expected)
      if peek(expected)
        if expected.is_a?(String)
          @pos += expected.length
        else
          @pos += 1
        end
      else
        raise "Expected '#{expected}' at position #{@pos}, got '#{@text[@pos]}'"
      end
    end

    def expect(expected)
      consume(expected)
    end

    def skip_whitespace
      while peek(/\s/)
        @pos += 1
      end
    end
  end

  def compile
    @scope_stack = [{ vars: {} }]
    @instructions = []
    transform(@ast, used: true)
    type_check
    @instructions
  end

  private

  def transform(node, used:)
    send("transform_#{node.type}", node, used:)
  end

  def transform_array_node(node, used:)
    node.elements.each { |element| transform(element, used:) }
    instruction = PushArrayInstruction.new(node.elements.size, line: node.location.start_line)
    @instructions << instruction
    @instructions << PopInstruction.new unless used
  end

  def transform_call_node(node, used:)
    node.receiver ? transform(node.receiver, used: true) : @instructions << PushSelfInstruction.new
    args = node.arguments&.arguments || []
    args.each { |arg| transform(arg, used: true) }
    instruction = CallInstruction.new(node.name, arg_count: args.size, line: node.location.start_line)
    @instructions << instruction
    @instructions << PopInstruction.new unless used
  end

  def transform_class_node(node, used:)
    name = node.constant_path.name
    superclass = node.superclass&.name
    instruction = ClassInstruction.new(name, line: node.location.start_line, superclass:)
    class_instructions = []
    with_instructions_array(class_instructions) { transform(node.body, used: false) } if node.body
    instruction.body = class_instructions
    @instructions << instruction
    @instructions << PushConstInstruction.new(instruction.name, line: node.location.start_line) if used
  end

  def transform_constant_read_node(node, used:)
    return unless used

    instruction = PushConstInstruction.new(node.name, line: node.location.start_line)
    @instructions << instruction
  end

  def transform_def_node(node, used:)
    @scope_stack << { vars: {} }
    params = node.parameters&.requireds || []
    instruction = DefInstruction.new(node.name, line: node.location.start_line)

    if (line_directives = @directives[node.location.start_line]) && (annotations = line_directives[:type_annotations])
      param_annotations = annotations.reject { |key, _| key == :return_type }
      instruction.type_annotations = param_annotations unless param_annotations.empty?
      instruction.return_type_annotation = annotations[:return_type] if annotations[:return_type]
    end

    def_instructions = []
    params.each_with_index do |param, index|
      i1 = PushArgInstruction.new(index, line: node.location.start_line)
      def_instructions << i1
      i2 = SetVarInstruction.new(param.name, line: node.location.start_line)
      def_instructions << i2
      instruction.params << param.name
    end
    with_instructions_array(def_instructions) { transform(node.body, used: true) }
    instruction.body = def_instructions
    @scope_stack.pop
    @instructions << instruction
    @instructions << PushStrInstruction.new(instruction.name, line: node.location.start_line) if used
  end

  def transform_else_node(node, used:)
    transform(node.statements, used:)
  end

  def transform_false_node(node, used:)
    return unless used

    instruction = PushFalseInstruction.new(line: node.location.start_line)
    @instructions << instruction
  end

  def transform_if_node(node, used:)
    transform(node.predicate, used: true)
    instruction = IfInstruction.new(line: node.location.start_line)
    instruction.used = used
    instruction.if_true = []
    with_instructions_array(instruction.if_true) do
      transform(node.statements, used: true)
      @instructions << PopInstruction.new unless used
    end
    instruction.if_false = []
    if node.subsequent
      with_instructions_array(instruction.if_false) do
        transform(node.subsequent, used: true)
        @instructions << PopInstruction.new unless used
      end
    elsif used
      raise SyntaxError, "if expression used as value must have an else clause (line #{node.location.start_line})"
    else
      # If statement without else clause - push nil but it won't be used
      with_instructions_array(instruction.if_false) { @instructions << PushNilInstruction.new }
    end
    @instructions << instruction
    @instructions << PopInstruction.new unless used
  end

  def transform_instance_variable_write_node(node, used:)
    transform(node.value, used: true)
    instruction = SetInstanceVarInstruction.new(node.name, line: node.location.start_line)

    if (line_directives = @directives[node.location.start_line]) &&
         (annotations = line_directives[:type_annotations]) && (type_annotation = annotations[node.name])
      instruction.type_annotation = type_annotation
    end

    @instructions << instruction
    @instructions << PopInstruction.new unless used
  end

  def transform_instance_variable_read_node(node, used:)
    return unless used
    instruction = PushInstanceVarInstruction.new(node.name, line: node.location.start_line)
    @instructions << instruction
  end

  def transform_integer_node(node, used:)
    return unless used

    instruction = PushIntInstruction.new(node.value, line: node.location.start_line)
    @instructions << instruction
  end

  def transform_local_variable_read_node(node, used:)
    return unless used

    instruction = PushVarInstruction.new(node.name, line: node.location.start_line)
    @instructions << instruction
  end

  def transform_local_variable_write_node(node, used:)
    transform(node.value, used: true)
    instruction = SetVarInstruction.new(node.name, line: node.location.start_line)

    if (line_directives = @directives[node.location.start_line]) &&
         (annotations = line_directives[:type_annotations]) && (type_annotation = annotations[node.name])
      instruction.type_annotation = type_annotation
    end

    @instructions << instruction
    @instructions << PushVarInstruction.new(node.name, line: node.location.start_line) if used
  end

  def transform_nil_node(node, used:)
    return unless used

    instruction = PushNilInstruction.new(line: node.location.start_line)
    @instructions << instruction
  end

  def transform_program_node(node, used:)
    transform(node.statements, used:)
  end

  def transform_statements_node(node, used:)
    node.body.each_with_index { |n, i| transform(n, used: used && i == node.body.size - 1) }
  end

  def transform_string_node(node, used:)
    return unless used

    instruction = PushStrInstruction.new(node.unescaped, line: node.location.start_line)
    @instructions << instruction
  end

  def transform_true_node(node, used:)
    return unless used

    instruction = PushTrueInstruction.new(line: node.location.start_line)
    @instructions << instruction
  end

  def transform_while_node(node, used:)
    instruction = WhileInstruction.new(line: node.location.start_line)

    instruction.condition = []
    with_instructions_array(instruction.condition) { transform(node.predicate, used: true) }

    # Transform body - the result is not used since while always returns nil
    instruction.body = []
    with_instructions_array(instruction.body) { transform(node.statements, used: false) }

    @instructions << instruction
    @instructions << PopInstruction.new unless used
  end

  def with_instructions_array(array)
    array_was = @instructions
    @instructions = array
    yield
  ensure
    @instructions = array_was
  end

  def type_check
    TypeChecker.new.analyze(@instructions)
  end

  def scope
    @scope_stack.last
  end

  def vars
    scope.fetch(:vars)
  end
end
